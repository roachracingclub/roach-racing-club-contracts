// SPDX-License-Identifier: MIT
// Roach Racing Club: the first strategic p2e game with deflationary mechanisms (https://roachracingclub.com/)
pragma solidity ^0.8.10;

import "../interfaces/IRoachNFT.sol";
import "./Operators.sol";


/// @title Genome generator
/// @author Shadow Syndicate / Andrey Pelipenko (kindex@kindex.lv)
/// @dev Should be deployed on cheap network, like Polygon
///      TokenSeed is generated using formula sha3(tokenId, traitBonus, vrfSeed, secretSeed, mintBlockHash)
///      Where:
///        tokenId - roach id.
///        traitBonus - trait bonus from whitelist, 0 for public sale.
///        vrfSeed - random value that is generated by Chainlink VRF after sha3(secretSeed) is published.
///        secretSeed - secret value, that is available only to developer team while genesis sale is not finished.
///        mintBlockHash - block hash of transaction, when roach was minted.
///      TokenSeed is unpredictable during the mint stage for all parties:
///        Developers can't predict vrfSeed and mintBlockHash
///        Miners can't predict secretSeed
///        Buyers can't predict both secretSeed and mintBlockHash
///      So TokenSeed is unpredictable but fixed and can be checked at any time after the reveal.
///      Genome is generated using tokenSeed. For the same tokenSeed, there will be equal genomes.
///      After the genesis sale is finished, the game will publish secretSeed, and anyone will be able to
///      check tokenSeeds and corresponding genomes.
///      Genome is signed by the secret private key and transferred from Polygon network to Ethereum
///      as part of the reveal process.
/// @dev GenomeProviderPolygon is used only for testing because of mocked VRF request.
///      GenomeProviderChainlink should be used for production.
contract GenomeProviderPolygon is Operators {

    uint constant TRAIT_COUNT = 6;
    uint constant MAX_BONUS = 25;

    struct TraitConfig {
        uint sum;
        uint[] slots;
        // data format: trait1, color1a, color1b, trait2, color2a, color2b, ...
        uint[] traitData;
        uint[] weight;
        uint[] weightMaxBonus;
    }

    mapping(uint => TraitConfig) public traits; // slot -> array of trait weight

    mapping(uint => uint) public vrfSeeds; // tokenId => random
    mapping(uint => uint) public seed1s; // tokenId => seed1
    mapping(uint => uint) public tokenSeeds; // tokenId => tokenSeed
    uint256 public secretSeedHash;

    event SecretSeed(uint256 secretSeedHash);
    event Reveal(uint tokenId, uint seed1, uint vrfSeed, uint tokenSeed);

    constructor(uint256 _secretSeedHash) {
        secretSeedHash = _secretSeedHash;
        emit SecretSeed(secretSeedHash);
    }

    function isRevealed(uint tokenId) external view returns (bool) {
        return tokenSeeds[tokenId] != 0;
    }

    function getTokenSeed(uint tokenId) external view returns (uint) {
        return tokenSeeds[tokenId];
    }

    function calculateSeed1(uint tokenId, uint traitBonus, uint secretSeed)
        public view returns (bytes32 seed1)
    {
        return keccak256(abi.encodePacked(tokenId, traitBonus, secretSeed));
    }

    /// @dev Function is used to check tokenSeed generation after secretSeed is published
    function calculateTokenSeed(uint tokenId, uint traitBonus, uint secretSeed, uint vrfSeed)
        external view returns (uint tokenSeed)
    {
        uint seed1 = uint(calculateSeed1(tokenId, traitBonus, secretSeed));
        return uint(keccak256(abi.encodePacked(seed1, vrfSeed)));
    }

    function calculateTokenSeedFromSeed1(uint seed1, uint vrfSeed)
        public view returns (uint token_seed)
    {
        return uint(keccak256(abi.encodePacked(seed1, vrfSeed)));
    }

    /// @dev Calculates genome for each roach using tokenSeed as seed
    function calculateGenome(uint256 tokenSeed, uint8 traitBonus) external view returns (bytes memory genome) {
        genome = _normalizeGenome(tokenSeed, traitBonus);
    }

    /// @dev Called only after contract is deployed and before genomes are generated
    // TODO: add owner sig
    function requestReveal(uint tokenId, uint seed1) external onlyOperator {
        require(seed1s[tokenId] == 0, "Can't call twice"); // TODO:
        seed1s[tokenId] = seed1;
        _requestRandomness(tokenId);
    }

    /// @dev Stub function for filling random, will be overriden in Chainlink version
    function _requestRandomness(uint tokenId) internal virtual {
        uint256 randomness = uint(keccak256(abi.encodePacked(block.timestamp)));
        _onRandomnessArrived(tokenId, randomness);
    }

    /// @dev Saves Chainlink VRF random value as vrfSeed
    function _onRandomnessArrived(uint tokenId, uint256 _randomness) internal {
        require(vrfSeeds[tokenId] == 0, "Can't call twice");
        vrfSeeds[tokenId] = _randomness;
        uint tokenSeed = calculateTokenSeedFromSeed1(seed1s[tokenId], vrfSeeds[tokenId]);
        tokenSeeds[tokenId] = tokenSeed;
        emit Reveal(tokenId, seed1s[tokenId], vrfSeeds[tokenId], tokenSeed);
    }

    /// @dev Setups genome configuration
    function setTraitConfig(
        uint traitIndex,
        uint[] calldata _slots,
        uint[] calldata _traitData,
        uint[] calldata _weight,
        uint[] calldata _weightMaxBonus
    )
        external onlyOperator
    {
        require(_weight.length == _weightMaxBonus.length, 'weight length mismatch');
        require(_slots.length * _weight.length == _traitData.length, '_traitData length mismatch');

        uint sum = 0;
        for (uint i = 0; i < _weight.length; i++) {
            sum += _weight[i];
        }
        traits[traitIndex] = TraitConfig(sum, _slots, _traitData, _weight, _weightMaxBonus);
    }

    function getWeightedRandom(uint traitType, uint randomSeed, uint bonus)
        internal view
        returns (uint choice, uint newRandomSeed)
    {
        TraitConfig storage config = traits[traitType];
        uint div = config.sum * MAX_BONUS;
        uint r = randomSeed % div;
        uint i = 0;
        uint acc = 0;
        while (true) {
            acc += config.weight[i] * (MAX_BONUS - bonus) + (config.weightMaxBonus[i] * bonus);
            if (acc > r) {
                choice = i;
                newRandomSeed = randomSeed / div;
                break;
            }
            i++;
        }
    }

    function _normalizeGenome(uint256 _randomness, uint8 _traitBonus) internal view returns (bytes memory) {

        bytes memory result = new bytes(32);
        result[0] = 0; // version
        for (uint i = 1; i <= TRAIT_COUNT; i++) {
            uint trait;
            (trait, _randomness) = getWeightedRandom(i, _randomness, _traitBonus);
            TraitConfig storage config = traits[i];
            for (uint j = 0; j < config.slots.length; j++) {
                result[config.slots[j]] = bytes1(uint8(config.traitData[trait * config.slots.length + j]));
            }
        }

        TraitConfig storage lastConfig = traits[TRAIT_COUNT];
        uint maxSlot = lastConfig.slots[lastConfig.slots.length - 1];
        for (uint i = maxSlot + 1; i < 32; i++) {
            result[i] = bytes1(uint8(_randomness & 0xFF));
            _randomness >>= 8;
        }
        return result;
    }
}
