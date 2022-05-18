## Roach Racing Club Contracts

```
RRC is a strategic racing game where you can breed and train your Roach runners. The results of each race are driven by real-world data and depend on your strategic and tactical decisions. The game introduces novel gameplay features and an evolutionary breeding model with deflationary mechanisms. 

```

## Contracts structure

# RoachNFT

Base NFT storage. Stores token ownership, genomes, parents.
Tokens are created during the Egg stage.
This contract is non-upgradable.

```
/// Returns contract level metadata for roach
function getRoach(roachId) 
    returns (genome, parents, creationTime, revealTime, generation, resistance, memory name) 
```

# Reveal

You should call reveal to finalize creating and give birth to the Roach token. There is a birth cooldown period (by default, 1 week).

```
/// Setups roach genome and give birth to it
function reveal(tokenId, genome, tokenSeed, sigV, sigR, sigS)
```

# GensisSale

Operates limited token sale. There can be only 10k Gen0 Roach tokens sold.

```
/// Returns current sale status:
function getSaleStatus(address account) external view 
    returns (stage, leftToMint, nextStageTimestamp, price, allowedToMint) 
```

```
/// Takes payment and mints new roaches on Presale Sale
function mintStage1(desiredCount, limitForAccount, traitBonus, syndicate, sigV, sigR, sigS)
```

```
Takes payment and mints new roaches on Public Sale
mintStage2(desiredCount, syndicate)
```

# GenomeProviderChainlink

Generates genome for each new Roach token using ChainLink VRF.
TokenSeed is generated using formula sha3(tokenId, traitBonus, vrfSeed, secretSeed, mintBlockHash)

Where:
* tokenId - roach id.
* traitBonus - trait bonus from whitelist, 0 for public sale.
* vrfSeed - random value that is generated by Chainlink VRF after sha3(secretSeed) is published.
* secretSeed - secret value, that is available only to developer team while genesis sale is not finished.
* mintBlockHash - block hash of transaction, when roach was minted.

TokenSeed is unpredictable during the mint stage for all parties:
* Developers can't predict vrfSeed and mintBlockHash
* Miners can't predict secretSeed
* Buyers can't predict both secretSeed and mintBlockHash

So TokenSeed is unpredictable but fixed and can be checked at any time after the reveal.
Genome is generated using tokenSeed. For the same tokenSeed, there will be equal genomes.
After the genesis sale is finished, the game will publish secretSeed, and anyone will be able to
check tokenSeeds and corresponding genomes.

Genome is signed by the secret private key and transferred from Polygon network to Ethereum
as part of the reveal process.

```
/// Calculates genome for each roach using tokenSeed as seed
function calculateGenome(tokenSeed, traitBonus)
```

# Metadata

An upgradeable contract that provides Metadata for Roach tokens.
Full metadata will be available only after Roach is born.

```
/// Returns token metadata URI according to IERC721Metadata
function tokenURI(tokenId)
```

## Deployment workflow

### Environment setup
We use [Brownie](https://eth-brownie.readthedocs.io/en/stable/install.html) framework for testing and development.

```bash
pip install eth-brownie
brownie pm install OpenZeppelin/openzeppelin-contracts@4.4.0
brownie pm install smartcontractkit/chainlink@1.2.1
npm -g i ganache-cli
```

### Testing

All tests can be launched using the command
```
brownie test
```

## Testnet deployment
Setup environment variables:
```
export DEPLOYER_PRIVATE_KEY=<deployer_account_private_key>
export WEB3_INFURA_PROJECT_ID=<infura_project_id>
export ETHERSCAN_TOKEN=<etherscan_api_token>
export POLYGONSCAN_TOKEN=<polygoncan_api_token>
```
Deploy command for Mainnet part:
```
brownie run ./deploy_eth.py --network=mainnet # prod
brownie run ./deploy_eth.py --network=rinkeby # testnet
```
Deploy command Polygon part:
```
brownie run ./deploy_polygon.py --network=polygon-main # prod
brownie run ./deploy_polygon.py --network=polygon-test # testnet
```
It is needed to request [testnet LINK](https://faucets.chain.link/rinkeby) to GenomeProviderChainlink contract.
After link token is transferred to GenomeProviderChainlink contract, you should call
```
function requestVrfSeed()
```

