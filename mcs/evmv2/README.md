# MAP Omnichain Service


## Setup Instructions
Edit the .env-example.txt file and save it as .env

The following node and npm versions are required
````
$ node -v
v14.17.1
$ npm -v
6.14.13
````

Configuration file description

PRIVATE_KEY User-deployed private key

INFURA_KEY User-deployed infura key

## Instruction
FeeCenter contract is a contract used to manage cross-chain charges

MapCrossChainService contract is suitable for evm-compatible chains and implements cross-chain logic

MAPCrossChainServiceRelay contract implements cross-chain logic and basic cross-chain control based on MapChain

TokenRegister contract is used to control the mapping of cross-chain tokens

The MAPVaultToken contract is a treasury and fee growth for users to provide cross-chain pledges

StandardToken contract is a token contract that has roles to control minting and destruction

MapCrossChainServiceProxy is the contract for MapCrossChainService upgrade

MAPCrossChainServiceRelayProxy is the contract for MAPCrossChainServiceRelay upgrade

## Build

```shell
git clone https://github.com/mapprotocol/map-contracts.git
cd map-contracts/mcs/evm/
npm install
```

## Test

```shell
npx hardhat test
```

## Deploy

### MOS Relay
The following steps help to deploy MOS relay contracts on Map mainnet or Makalu testnet

1. Deploy Fee Center and Token Register
```
npx hardhat deploy --tags FeeCenter --network <network>
npx hardhat deploy --tags TokenRegister --network <network>
````
2. Deploy MOS Relay

```
npx hardhat relayDeploy --wrapped <wrapped token> --lightnode <lightNodeManager address> --network <network>
````

* `wrapped token` is wrapped MAP token address on MAP mainnet or MAP Makalu.
* `lightNodeManager address` is the light client mananger address deployed on MAP mainnet or MAP Makalu. See [here](../protocol/README.md) for more information.

3. Init MOS Relay
```
npx hardhat relayInit --feeCenter <feeCenter address> --tokenRegister <token register address> --network <network>
````


4. FeeCenter sets fee distribution
````
npx hardhat feeCenterSetDistributeRate --token <vault address> --rate <rate 0-1000000> --network <network>
````

### MOS on EVM Chains

1. Deploy
```
npx hardhat mosDeploy --wrapped <native wrapped address> --lightnode <lightnode address> --network <network>
```

2. Set MOS Relay Address
The following command on the EVM compatible chain
```
npx hardhat mosSetRelay --relay <Relay address> --chain <map chainId> --network <network>
```

3. Register
   The following command applies to the cross-chain contract configuration of Map mainnet and Makalu testnet
```
npx hardhat registerMCS --address <mapCrossChainService address> --chain <mapCrossChainService chainId> --network <network>
```

### MOS on other chain


The following four commands are generally applicable to Map mainnet and Makalu testnet
```
npx hardhat mcsSetChain --name <chain name> --chain <chain id> --network <network>
```


## Configure

### Deploy Token

1. Deploy a mintable Token
````
npx hardhat deployToken --name <token name > --symbol <token symbol> --balance <init balance> --network <network>
````

2. Grant Mint Role to relay or mos contract
````
npx hardhat grantToken --token <token address > --minter <adress/mos/relay> --network <network>
````

### Register Token

1. Relay Chain Create VaultToken

````
npx hardhat vaultInitToken --token <relaychain token address> --name <vault token name> --symbol <vault token symbol> --network <network>
````
2. Relay Chain FeeCenter sets up the treasury and token binding
````
npx hardhat feeSetTokenVault --vault <vault token address> --token <relaychain mapping token address> --network <network>
````

3. Relay Chain sets the token decimal
   Note the mcsids and tokendecimals parameters can be filled with one or more words separated by ',' (eg 1,2,96 18,18,24)
````
npx hardhat tokenRegisterSetTokenDecimals --token <token address> --chains <Multiple chainIds (1,2,96)> --decimals <token decimals (18,18,24)> --network <network>
````

4. Relay chain sets the token mintable


### Add Cross-chain Token

1. Relay Chain FeeCenter sets the token cross-chain fee ratio
````
npx hardhat feeSetTokenGasFee --token <token address> --chain <target chain id>  --min <minimum fee value (WEI)> --max <maximum fee value (WEI)> --rate <fee rate 0-1000000> --network <network>
````

2. Relay Chain Bind the token mapping relationship between the two chains that requires cross-chain
````
npx hardhat tokenRegister --mapToken <token address> --chain <cross-chain id> --token <cross-chain token>  --network <network>
````

3. Relay Chain sets the decimal for cross-chain tokens
   Note the mcsids and tokendecimals parameters can be filled with one or more words separated by ',' (eg 1,2,96 18,18,24)
````
npx hardhat relaySetTokenDecimals --token <token address> --chains <Multiple chainIds (1,2,96)> --decimals <token decimals (18,18,24)> --network <network>
````

4. Altchain sets bridge token
````
npx hardhat relaySetTokenDecimals --token <token address> --chains <Multiple chainIds (1,2,96)> --decimals <token decimals (18,18,24)> --network <network>
````

5. Altchain sets token mintable

## Upgrade

When have a better cross-chain idea, we can upgrade the cross-chain contract through the following commands.

Please execute the following command on the EVM compatible chain

```
npx hardhat deploy --tags MapCrossChainServiceProxyUp --network <network>
```

Please execute the following command on Map mainnet or Makalu testnet
```
npx hardhat deploy --tags MAPCrossChainServiceRelayProxyUp --network <network>
```


## MOS parameter setting

- Setting a Token can be cross-chain or canceled

```solidity
function setCanBridgeToken(address token, uint chainId, bool canBridge) public 	onlyManager {
        canBridgeToken[token][chainId] = canBridge;
    }
```



MAP Cross Chain Service Relay parameter setting

- Set cross-chain fees for FeeCenter contracts

  ```solidity
  function setChainTokenGasFee(uint to, address token, uint lowest, uint highest,uint proportion) external onlyManager {
      chainTokenGasFee[to][token] = gasFee(lowest,highest,proportion);
  }
  ```

- Set the decimals of the cross-chain token

  ```solidity
  function setTokenOtherChainDecimals(bytes memory selfToken, uint256 chainId, uint256 decimals) external onlyManager {
      tokenOtherChainDecimals[selfToken][chainId] = decimals;
  }
  ```

- Set the number of cross-chain vault tokens (if needed)

  ```solidity
  function setVaultBalance(uint256 tochain, address token, uint256 amount) external onlyManager {
      vaultBalance[tochain][token] = amount;
  }
  ```

- Set other chain msc contract address for verification

  ```solidity
  function setBridgeAddress(uint256 _chainId, bytes memory _addr) external onlyManager {
      bridgeAddress[_addr] = _chainId;
  }
  ```