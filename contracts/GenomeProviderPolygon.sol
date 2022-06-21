// SPDX-License-Identifier: MIT
// Roach Racing Club: the first strategic p2e game with deflationary mechanisms (https://roachracingclub.com/)
/*
______                 _      ______           _               _____ _       _
| ___ \               | |     | ___ \         (_)             /  __ \ |     | |
| |_/ /___   __ _  ___| |__   | |_/ /__ _  ___ _ _ __   __ _  | /  \/ |_   _| |__
|    // _ \ / _` |/ __| '_ \  |    // _` |/ __| | '_ \ / _` | | |   | | | | | '_ \
| |\ \ (_) | (_| | (__| | | | | |\ \ (_| | (__| | | | | (_| | | \__/\ | |_| | |_) |
\_| \_\___/ \__,_|\___|_| |_| \_| \_\__,_|\___|_|_| |_|\__, |  \____/_|\__,_|_.__/
                                                        __/ |
                                                       |___/
.................................,,:::,...........
..............................,:;;;:::;;;,........
...............,,,,,.........:;;,......,;+:.......
.............:::,,,::,.....,+;,..........:*;......
...........,;:.......,:,..,+:.............:*:.....
..........:;,..........:,.+:...............*+.....
.........,+,..........,,:;+,,,.............;*,....
.........+:.......,:+?SS####SS%*;,.........;*:....
........:+.....,;?S##############S?:.......;*,....
........;+....;?###############%??##+......+*,....
........:+...,%SS?;?#########@@S?++S#:....,+;.....
........,+:..,%S%*,*#####SSSSSS%*;,%S,............
.........;;,..;SS%S#####SSSS%%%?+:*%;.............
..........,....:%########SSS%%?*?%?,..............
.............,,,.+S##@#?+;;*%%SS%;................
.........,,.,+++;:+%##?+*+:,?##S+;:,..............
....,,;+*SS*??***++?S#S?*+:,%S%%%%%?+:,......,....
,:;**???*?#@##S?***++*%%*;,:%%%%**?%%?;,,.,;?%?%??
????*+;:,,*####S%%?*+;:;;,,+#S%%%?*?%??+;*%S?*%SSS
*+;:,....,%@S####SS%?*+:::*S@#%%%%????%%S%*;::,,,:
.........+@@S%S####S#@%?%%SS#@SS%%%%SS%*++;,......
........,%@@S%%S#@##@#%%%%%%S@##SSS%*+*?%?;,......
........:#@@%%%%%S@S##%%%%%%%#@##?++**%%S%+:......
........+@@#%SS%%%SSS?S%%%%%%S@SS?????%?S%*;,.....
........?@@@%%%%%%%%%%%%%%%%%%%%%%??**?%#%%;,.....
*/
pragma solidity ^0.8.10;

import "../interfaces/IRoachNFT.sol";
import "./Operators.sol";

/// @title Genome generator
/// @author Shadow Syndicate / Andrey Pelipenko (kindex@kindex.lv)
/// @dev Should be deployed on cheap network, like Polygon
///      TokenSeed is generated using formula sha3(tokenId, traitBonus, devSeed, vrfSeed)
///      Where:
///        tokenId - roach id.
///        traitBonus - trait bonus from whitelist, 0 for public sale.
///        devSeed - secret value, that is available only to developer team while NFT is not revealed
///        vrfSeed - random value that is generated by Chainlink VRF after sha3(devSeed) is published.
///      TokenSeed is unpredictable during the mint stage for all parties:
///        Developers can't predict vrfSeed and mintBlockHash
///        Miners can't predict devSeed
///        Buyers can't predict devSeed and vrfSeed
///      So TokenSeed is unpredictable but fixed and can be checked at any time after the reveal.
///      Genome is generated using tokenSeed. For the same tokenSeed, there will be equal genomes.
///      After the genesis sale is finished, the game will publish devSeed, and anyone will be able to
///      check tokenSeeds and corresponding genomes.
///      Genome is signed by the secret private key and transferred from Polygon network to Ethereum
///      as part of the reveal process.
/// @dev GenomeProviderPolygon is used only for testing because of mocked VRF request.
///      GenomeProviderChainlink should be used for production.
contract GenomeProviderPolygon is Operators {

    uint constant TRAIT_COUNT = 6;
    uint constant MAX_BONUS = 25;

    struct TraitConfig {
        uint32 sum;
        uint8[] slots;
        // data format: trait1, color1a, color1b, trait2, color2a, color2b, ...
        uint8[] traitData;
        uint16[] weight;
        uint16[] weightMaxBonus;
    }

    mapping(uint => TraitConfig) public traits; // slot -> array of trait weight

    struct Roach {
        uint256 vrfSeed;
        uint256 tokenSeed;
        uint256 devSeedHash;
        uint256 devSeed;
        bytes genome;
        uint64 revealTime;
        uint8 traitBonus;
        bool requested;
    }

    mapping(uint => Roach) public roach;

    event DevSeedHash(uint indexed tokenId, uint256 devSeedHash);
    event GenomeSaved(uint indexed tokenId, uint devSeed, uint tokenSeed, bytes genome);
    event RevealVrf(uint indexed tokenId, uint vrfSeed);
    event RevealRequest(uint indexed tokenId, uint8 traitBonus, string ownerSig);

    function _publishDevSeedHash(uint tokenId, uint _devSeedHash) internal {
        Roach storage _roach = roach[tokenId];
        require(_roach.devSeedHash == 0, "Can't call twice");
        _roach.devSeedHash = _devSeedHash;
        emit DevSeedHash(tokenId, _devSeedHash);
    }

    function publishDevSeedHash(uint tokenId, uint _devSeedHash) external onlyOperator {
        _publishDevSeedHash(tokenId, _devSeedHash);
    }

    function publishDevSeedHashBatch(uint startTokenId, uint[] calldata _devSeedHashes) external onlyOperator {
        for (uint i = 0; i < _devSeedHashes.length; i++) {
            _publishDevSeedHash(startTokenId + i, _devSeedHashes[i]);
        }
    }

    function isRevealed(uint tokenId) external view returns (bool) {
        return roach[tokenId].revealTime != 0;
    }

    function getRoach(uint tokenId) external view returns (Roach memory) {
        return roach[tokenId];
    }

    /// @dev Function is used to check tokenSeed generation after devSeed is published
    function calculateTokenSeed(uint tokenId, uint traitBonus, uint devSeed, uint vrfSeed)
        public view returns (uint tokenSeed)
    {
        return uint(keccak256(abi.encodePacked(tokenId, traitBonus, devSeed, vrfSeed)));
    }

    /// @dev Calculates genome for each roach using tokenSeed as seed
    function calculateGenome(uint256 tokenSeed, uint8 traitBonus) external view returns (bytes memory genome) {
        genome = _normalizeGenome(tokenSeed, traitBonus);
    }

    /// @dev Called only after contract is deployed and before genomes are generated
    function requestReveal(uint tokenId, uint8 traitBonus, uint256 devSeedHash, string calldata ownerSig)
        external onlyOperator
    {
        Roach storage _roach = roach[tokenId];
        require(!_roach.requested, "Can't call twice");
        _roach.requested = true;
        _roach.devSeedHash = devSeedHash;
        _roach.traitBonus = traitBonus;
        _requestRandomness(tokenId);
        emit RevealRequest(tokenId, traitBonus, ownerSig);
    }

    /// @dev Stub function for filling random, will be overriden in Chainlink version
    function _requestRandomness(uint tokenId) internal virtual {
        uint256 randomness = uint(keccak256(abi.encodePacked(block.timestamp)));
        _onRandomnessArrived(tokenId, randomness);
    }

    /// @dev Saves Chainlink VRF random value as vrfSeed
    function _onRandomnessArrived(uint tokenId, uint256 _randomness) internal {
        Roach storage _roach = roach[tokenId];
        require(_roach.vrfSeed == 0, "Can't call twice");
        _roach.vrfSeed = _randomness;
        _roach.revealTime = uint64(block.timestamp);
        emit RevealVrf(tokenId, _roach.vrfSeed);
    }

    function calculateDevSeedHash(uint _devSeed) public view returns (uint) {
        return uint(keccak256(abi.encodePacked(_devSeed)));
    }

    function saveGenome(uint tokenId, uint _devSeed) external onlyOperator {
        Roach storage _roach = roach[tokenId];
        require(_roach.devSeed == 0, "Can't call twice");
        require(_roach.vrfSeed != 0, "VRF is set");
        require(_roach.devSeedHash == calculateDevSeedHash(_devSeed), "devSeed hash correct");
        _roach.devSeed = _devSeed;
        _roach.tokenSeed = calculateTokenSeed(tokenId, _roach.traitBonus, _roach.devSeed, _roach.vrfSeed);
        _roach.genome = _normalizeGenome(_roach.tokenSeed, _roach.traitBonus);
        emit GenomeSaved(tokenId, _roach.devSeed, _roach.tokenSeed, _roach.genome);
    }


    /// @dev Setups genome configuration
    function setTraitConfig(
        uint traitIndex,
        uint8[] calldata _slots,
        uint8[] calldata _traitData,
        uint16[] calldata _weight,
        uint16[] calldata _weightMaxBonus
    )
        external onlyOperator
    {
        require(_weight.length == _weightMaxBonus.length, 'weight length mismatch');
        require(_slots.length * _weight.length == _traitData.length, '_traitData length mismatch');

        uint32 sum = 0;
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
