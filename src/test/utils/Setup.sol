// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {StrategyMainnet, ERC20} from "../../StrategyMainnet.sol";
import {StrategyOp} from "../../StrategyOp.sol";
import {StrategyArb} from "../../StrategyArb.sol";

import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {IStrategyInterfaceRamses} from "../../interfaces/IStrategyInterface.sol";
import {IStrategyInterfaceVelo} from "../../interfaces/IStrategyInterface.sol";

import {IWhitelist} from "../../interfaces/IWhitelist.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

import {ITransmuter} from "../../interfaces/ITransmuter.sol";
import {ITransmuterBuffer} from "../../interfaces/ITransmuterBuffer.sol";
import {IAlchemist} from "../../interfaces/IAlchemist.sol";

import {YieldTokenMock} from "../../mock/YieldTokenMock.sol";
import {TokenAdapterMock} from "../../mock/TokenAdapterMock.sol";

import {ICurveStableSwapNG} from "../../interfaces/ICurve.sol";
import {IVeloRouter} from "../../interfaces/IVelo.sol";
import {IRamsesRouter} from "../../interfaces/IRamses.sol";


interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract Setup is ExtendedTest, IEvents {
    // Contract instances that we will use repeatedly.

    struct config {
        address asset;
        address underlying;
        address whitelist;
        address transmuter;
        address transmuterBuffer;
        address alchemist;
        address keeper;
        address whale;
    }

    ERC20 public asset;
    // Underlying ERC20 of AL Token -> we will use this to interact with transmuter to allow exchanges
    // I.e. as per : https://github.com/alchemix-finance/v2-foundry/blob/reward-collector-fix/test/TransmuterV2.spec.ts
    ERC20 public underlying;
    IStrategyInterface public strategy;
    IStrategyInterfaceRamses public strategyRamses;
    IStrategyInterfaceVelo public strategyVelo;

    IWhitelist public whitelist;

    ITransmuter public transmuter;
    ITransmuterBuffer public transmuterBuffer;
    IAlchemist public alchemist;

    mapping(string => address) public tokenAddrs;
    mapping(string => config) public configs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public user2 = address(9);
    address public keeper = address(4);
    address public management = address(1);
    address public mockYieldToken;

    address public performanceFeeRecipient = address(3);
    //address public buffer = 0xbc2FB245594a68c927C930FBE2d00680A8C90B9e;
    address public whale;
    address public transmuterKeeper;

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e19;
    uint256 public minFuzzAmount = 1e17;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        _setTokenAddrs();
        _setConfig();

        config memory stratConfig;
        if (block.chainid == 1) {
            // Mainnet
            stratConfig = configs["mainnet"];

        } else if (block.chainid == 10) {
            // OP
            stratConfig = configs["OP"];
        } else if (block.chainid == 42161) {
            // ARB
            stratConfig = configs["ARB"];
        } else {
            revert("Chain ID not supported");
        }

        whale = stratConfig.whale;
        // Set asset
        asset = ERC20(stratConfig.asset);
        underlying = ERC20(stratConfig.underlying);

        // Set decimals
        decimals = asset.decimals();

        // Deploy strategy and set variables
        
        transmuter = ITransmuter(stratConfig.transmuter);
        transmuterBuffer = ITransmuterBuffer(stratConfig.transmuterBuffer);
        alchemist = IAlchemist(stratConfig.alchemist);
        transmuterKeeper = stratConfig.keeper;

        strategy = IStrategyInterface(setUpStrategy());

        // whitelist hte strategy
        whitelist = IWhitelist(stratConfig.whitelist);
        vm.prank(whitelist.owner());
        whitelist.add(address(strategy));

        vm.prank(whitelist.owner());
        whitelist.add(user2);

        factory = strategy.FACTORY();

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");

        if (block.chainid == 1) {
            // Mainnet
            addCurveRoute();
        }


    }

    function setUpStrategy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        address _strat;
        if (block.chainid == 1) {
            // Mainnet
            _strat = address(new StrategyMainnet(
                address(asset),
                address(transmuter),
                "Tokenized Strategy")
            );



        } else if (block.chainid == 10) {
            _strat = address(new StrategyOp(
                address(asset),
                address(transmuter),
                "Tokenized Strategy")
            );

        } else if (block.chainid == 42161) {
            _strat = address(new StrategyArb(
                address(asset),
                address(transmuter),
                "Tokenized Strategy")
            );
        } else {
            revert("Chain ID not supported");
        }

        IStrategyInterface _strategy = IStrategyInterface(_strat);
        // set keeper
        _strategy.setKeeper(keeper);
        // set treasury
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        // set management of the strategy
        _strategy.setPendingManagement(management);

        vm.prank(management);
        _strategy.acceptManagement();

        return address(_strategy);
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        //airdrop(asset, _user, _amount);
        vm.prank(whale);
        asset.transfer(_user, _amount);
        
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(
            address(_strategy)
        );
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    function _setConfig() internal {

        configs["mainnet"] = config(
            0x0100546F2cD4C9D97f798fFC9755E47865FF7Ee6,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0x211C74DB951c161c5A379363716EbDca5125EF59,
            0x03323143a5f0D0679026C2a9fB6b0391e4D64811,
            0xbc2FB245594a68c927C930FBE2d00680A8C90B9e,
            0x062Bf725dC4cDF947aa79Ca2aaCCD4F385b13b5c,
            0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9,
            0xBD28e1B15EcbE72706A445f77bd17FCd8Fe6f652
        );

        configs["OP"] = config(
            0x3E29D3A9316dAB217754d13b28646B76607c5f04,
            0x4200000000000000000000000000000000000006,
            0xfa6A5D33e18CB0d52991536ab15750fB13119E45,
            0xb7C4250f83289ff3Ea9f21f01AAd0b02fb19491a,
            0x7f50923EE8E2BC3596a63998495baf2948a28f68,
            0xe04Bb5B4de60FA2fBa69a93adE13A8B3B569d5B4,
            0xC224bf25Dcc99236F00843c7D8C4194abE8AA94a,
            0xC224bf25Dcc99236F00843c7D8C4194abE8AA94a

        );
        
        configs["ARB"] = config(
            0x17573150d67d820542EFb24210371545a4868B03, 
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
            0xd691f5B477092c164ca4c75a23c3C9589E197F99 ,
            0x1EB7D78d7f6D73e5de67Fa62Fd8b55c54Aa9c0D4,
            0xECAd08EE07f1AA87f3E080997eBa6d02d28bb9D2,
            0x654e16a0b161b150F5d1C8a5ba6E7A7B7760703A,
            //0x7e108711771DfdB10743F016D46d75A9379cA043,
            0x886FF7a2d46dcc2276e2fD631957969441130847,
            0xb8950c47E8B9e539601cB47A167DE8bf4Cb1289E
        );
        
    }
    


    function deployMockYieldToken() public {
        mockYieldToken = address(
            new YieldTokenMock("Mock Yield Token", "MYT", underlying)
        );
    }

    function addCurveRoute() public {
            vm.label(0x8eFD02a0a40545F32DbA5D664CbBC1570D3FedF6, "curvePool");
            address[11] memory crvRoute;
            crvRoute[0] = address(underlying); // Underlying address
            crvRoute[1] = address(0x8eFD02a0a40545F32DbA5D664CbBC1570D3FedF6); // Pool address
            crvRoute[2] = address(asset);
            // Fill the rest of the route with zero addresses
            for (uint i = 4; i < 11; i++) {
                crvRoute[i] = address(0);
            }

            uint256[5][5] memory swapParams;
            // For this simple swap, we only need to set the first array
            swapParams[0] = [
                uint256(1), // i: index of underlying (WETH)
                uint256(0), // j: index of asset (alETH)
                uint256(1), // swap_type: 1 for standard token exchange
                uint256(1), // pool_type: 1 - stable
                uint256(2)  // n_coins: 2 for a two-coin pool
            ];

            // We don't need to specify pools for this simple swap
            address[5] memory pools;
            for (uint i = 0; i < 5; i++) {
                pools[i] = address(0);
            }

            vm.prank(management);
            IStrategyInterface(address(strategy)).addRoute(
                crvRoute,
                swapParams,
                pools
            );

    }

    function addMockYieldToken() public {

        address adapter = address(new TokenAdapterMock(mockYieldToken));

        // ARB 0x886FF7a2d46dcc2276e2fD631957969441130847

        vm.prank(transmuterKeeper);
        alchemist.addYieldToken(mockYieldToken, IAlchemist.YieldTokenConfig(adapter, 1,  type(uint256).max, 1));

        vm.prank(transmuterKeeper);
        alchemist.setYieldTokenEnabled(mockYieldToken, true);
    }

    function depositToAlchemist(uint256 _amount) public {
        airdrop(underlying, user2, _amount);
        vm.prank(user2);
        underlying.approve(address(alchemist), _amount);

        address _whitelist = alchemist.whitelist();
        address owner = IWhitelist(_whitelist).owner();

        vm.prank(owner);
        IWhitelist(_whitelist).add(user2);

        vm.prank(user2);
        alchemist.depositUnderlying(mockYieldToken, _amount, user2, 0);

        //vm.prank(user2);
        //alchemist.mint(_amount * 7 / 10, user2);

    }

    function airdropToMockYield(uint256 _amount) public {
        airdrop(underlying, mockYieldToken, _amount);
    }

    function harvestMockYield() public {
        vm.prank(transmuterKeeper);
        alchemist.harvest(mockYieldToken, 0);
    }

    function smallCurveSwap() public {

        uint256 smallAmount = 1e10;

        airdrop(underlying, user2, smallAmount);
        address curvePool = 0x8eFD02a0a40545F32DbA5D664CbBC1570D3FedF6;
        vm.prank(user2);
        underlying.approve(curvePool, smallAmount);

        ICurveStableSwapNG(curvePool).exchange(1, 0, smallAmount, 0, address(this));

    }


}
