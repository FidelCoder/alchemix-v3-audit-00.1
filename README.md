# Alchemix


### Prize Pool 

- Total Pool - 16,653 OP
- H/M -  15,800 OP
- Low - 853 OP

- Starts: Monday December 16, 2024 
- Ends: Monday December 23, 2024

- nSLOC: 253

[//]: # (contest-details-open)

## About the Project

The strategy utilises Yearn V3 strategy template & builds on top of Alchemix providing an automated strategy which allows users to earn yield on Alchemix tokens (primiarly alETH) by taking advantage of potential depegs. The strategy deposits to Alchemix's transmuter contract, an external keeper can claim alETH for WETH & execute a swap back to alETH at a premium to take advantage of any depeg of alETH vs WETH. 


[Documentation](https://docs.alchemix.fi/)
[Transmuter](https://docs.alchemix.fi/alchemix-ecosystem/transmuter)
[Website](https://alchemix.fi/)
[Twitter](www.twitter.com/AlchemixFi)

## Actors


Keeper: Has permission to call claimAndSwap (i.e. complete a claim from the transmuter for underlying asset & swap back to alx token at premium)
Owner: Strategy owner - can call onlyOwner functions i.e. emergency functions within Yearn V3 tokenized strategy mix
Manager: Can call functions with onlyManagement modifier - in this strategy this allows for swap routes to be added (i.e. when swapping via Velo which route is used)
Depositor: Account that deposits the asset and holds Shares

Note there are additional roles within the Yearn V3 tokenized strategy mix that are not used in this strategy & out of scope.
Details here : https://docs.yearn.fi/developers/v3/strategy_writing_guide

[//]: # (contest-details-close)

[//]: # (scope-open)

## Scope (contracts)

```
src/
├── StrategyOp.sol
├── StrategyMainnet.sol
├── StrategyArb.sol
├── interfaces
│   ├── IAlchemist.sol
│   └── ITransmuter.sol
│   └── IVeloRouter.sol
```

## Compatibilities

Blockchains:
    - Optimism
Tokens:
    - WETH
    - alETH
    - yTokens (based on Yearn V3 tokenized strategy mix : https://github.com/yearn/tokenized-strategy-foundry-mix)


[//]: # (scope-close)

[//]: # (getting-started-open)

## Setup

- First you will need to install [Foundry](https://book.getfoundry.sh/getting-started/installation).
NOTE: If you are on a windows machine it is recommended to use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install)
- Install [Node.js](https://nodejs.org/en/download/package-manager/)

### Set your environment Variables

Use the `.env.example` template to create a `.env` file and store the environement variables. You will need to populate the `RPC_URL` for the desired network(s). RPC url can be obtained from various providers, including [Ankr](https://www.ankr.com/rpc/) (no sign-up required) and [Infura](https://infura.io/).

Use .env file

1. Make a copy of `.env.example`
2. Add the value for `OPTIMISM_RPC_URL` and other example vars
     NOTE: If you set up a global environment variable, that will take precedence.

### Build the project

```sh
make build
```

Run tests

```sh
make test-op
```

[//]: # (getting-started-close)

[//]: # (known-issues-open)

## Known Issues

No known issues reported

[//]: # (known-issues-close)
