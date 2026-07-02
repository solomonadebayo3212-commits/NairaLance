// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {FreelanceEscrow} from "../src/FreelanceEscrow.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract FreelanceEscrowTest is Test {

    FreelanceEscrow public escrow;
    MockERC20       public cNGN;
    MockERC20       public usdt;

    address owner      = makeAddr("owner");
    address client     = makeAddr("client");
    address freelancer = makeAddr("freelancer");
    address stranger   = makeAddr("stranger");

    uint256 constant JOB_AMOUNT      = 100_000e18;
    uint256 constant CLIENT_DEPOSIT  = 106_000e18;
    uint256 constant FREELANCER_GETS = 96_000e18;
    uint256 constant PLATFORM_FEE    = 10_000e18;
    uint256 constant DEADLINE_SECS   = 7 days;
    string  constant WORK_LINK       = "https://github.com/solomon/nairalance-delivery";

    function setUp() public {
        vm.startPrank(owner);
        cNGN   = new MockERC20("cNGN", "cNGN", 18);
        usdt   = new MockERC20("USDT", "USDT", 6);
        escrow = new FreelanceEscrow(address(cNGN), address(usdt));
        vm.stopPrank();
        cNGN.mint(client, 1_000_000e18);
        usdt.mint(client, 1_000_000e6);
    }

    function _createJob() internal returns (uint256 jobId) {
        vm.startPrank(client);
        cNGN.approve(address(escrow), CLIENT_DEPOSIT);
        jobId = escrow.createJob(address(cNGN), JOB_AMOUNT, DEADLINE_SECS, "Build a DeFi dashboard");
        vm.stopPrank();
    }

    function _createAndAcceptJob() internal returns (uint256 jobId) {
        jobId = _createJob();
        vm.prank(freelancer);
        escrow.acceptJob(jobId);
    }

    function _createAcceptAndSubmit() internal returns (uint256 jobId) {
        jobId = _createAndAcceptJob();
        vm.prank(freelancer);
        escrow.submitWork(jobId, WORK_LINK);
    }

    // ── HAPPY PATH ──────────────────────────────────────────────────────────

    function test_CreateJob_cNGN_correctDepositCalculated() public {
        uint256 jobId = _createJob();
        FreelanceEscrow.Job memory job = escrow.getJob(jobId);
        assertEq(job.jobAmount,     JOB_AMOUNT);
        assertEq(job.clientDeposit, CLIENT_DEPOSIT);
        assertEq(address(job.token), address(cNGN));
        assertEq(uint8(job.status), uint8(FreelanceEscrow.JobStatus.Open));
        assertEq(cNGN.balanceOf(address(escrow)), CLIENT_DEPOSIT);
    }

    function test_CreateJob_USDT_correctDepositCalculated() public {
        uint256 usdtJobAmount = 1_000e6;
        uint256 usdtDeposit   = 1_060e6;
        vm.startPrank(client);
        usdt.approve(address(escrow), usdtDeposit);
        uint256 jobId = escrow.createJob(address(usdt), usdtJobAmount, DEADLINE_SECS, "Design a logo");
        vm.stopPrank();
        assertEq(escrow.getJob(jobId).clientDeposit, usdtDeposit);
    }

    function test_AcceptJob_success() public {
        uint256 jobId = _createJob();
        vm.prank(freelancer);
        escrow.acceptJob(jobId);
        FreelanceEscrow.Job memory job = escrow.getJob(jobId);
        assertEq(job.freelancer,    freelancer);
        assertEq(uint8(job.status), uint8(FreelanceEscrow.JobStatus.Active));
    }

    function test_SubmitWork_success_withAnyLink() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(freelancer);
        escrow.submitWork(jobId, "https://github.com/solomon/project");
        FreelanceEscrow.Job memory job = escrow.getJob(jobId);
        assertEq(uint8(job.status), uint8(FreelanceEscrow.JobStatus.Submitted));
        assertEq(job.workLink, "https://github.com/solomon/project");
    }

    function test_SubmitWork_success_withIPFSLink() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(freelancer);
        escrow.submitWork(jobId, "ipfs://QmXYZ1234567890abcdef");
        assertEq(escrow.getJob(jobId).workLink, "ipfs://QmXYZ1234567890abcdef");
    }

    function test_ApproveAndRelease_freelancerReceivesCorrectAmount() public {
        uint256 jobId = _createAcceptAndSubmit();
        vm.prank(client);
        escrow.approveAndRelease(jobId);
        assertEq(cNGN.balanceOf(freelancer), FREELANCER_GETS);
    }

    function test_ApproveAndRelease_platformEarns10Percent() public {
        uint256 jobId = _createAcceptAndSubmit();
        vm.prank(client);
        escrow.approveAndRelease(jobId);
        assertEq(escrow.platformFeesAccumulated(address(cNGN)), PLATFORM_FEE);
    }

    function test_ClaimPayment_afterDeadline_freelancerProtected() public {
        uint256 jobId = _createAcceptAndSubmit();
        vm.warp(block.timestamp + DEADLINE_SECS + 1);
        vm.prank(freelancer);
        escrow.claimPayment(jobId);
        assertEq(cNGN.balanceOf(freelancer), FREELANCER_GETS);
        assertEq(escrow.platformFeesAccumulated(address(cNGN)), PLATFORM_FEE);
    }

    function test_ClaimRefund_freelancerNeverDelivered_fullRefund() public {
        uint256 jobId = _createAndAcceptJob();
        vm.warp(block.timestamp + DEADLINE_SECS + 1);
        uint256 before = cNGN.balanceOf(client);
        vm.prank(client);
        escrow.claimRefund(jobId);
        assertEq(cNGN.balanceOf(client), before + CLIENT_DEPOSIT);
    }

    function test_ClaimRefund_platformEarnsNothing() public {
        uint256 jobId = _createAndAcceptJob();
        vm.warp(block.timestamp + DEADLINE_SECS + 1);
        vm.prank(client);
        escrow.claimRefund(jobId);
        assertEq(escrow.platformFeesAccumulated(address(cNGN)), 0);
    }

    function test_ResolveDispute_100percentToFreelancer() public {
        uint256 jobId = _createAcceptAndSubmit();
        vm.prank(client); escrow.raiseDispute(jobId);
        vm.prank(owner);  escrow.resolveDispute(jobId, 100);
        assertEq(cNGN.balanceOf(freelancer), FREELANCER_GETS);
        assertEq(escrow.platformFeesAccumulated(address(cNGN)), PLATFORM_FEE);
    }

    function test_ResolveDispute_100percentToClient() public {
        uint256 jobId = _createAcceptAndSubmit();
        uint256 before = cNGN.balanceOf(client);
        vm.prank(client); escrow.raiseDispute(jobId);
        vm.prank(owner);  escrow.resolveDispute(jobId, 0);
        assertEq(cNGN.balanceOf(client), before + FREELANCER_GETS);
    }

    function test_ResolveDispute_70_30Split() public {
        uint256 jobId = _createAcceptAndSubmit();
        vm.prank(client); escrow.raiseDispute(jobId);
        vm.prank(owner);  escrow.resolveDispute(jobId, 70);
        assertEq(cNGN.balanceOf(freelancer), (FREELANCER_GETS * 70) / 100);
    }

    function test_ResolveDispute_platformAlwaysEarns10Percent() public {
        uint256 jobId = _createAcceptAndSubmit();
        vm.prank(client); escrow.raiseDispute(jobId);
        vm.prank(owner);  escrow.resolveDispute(jobId, 50);
        assertEq(escrow.platformFeesAccumulated(address(cNGN)), PLATFORM_FEE);
    }

    function test_WithdrawFees_ownerReceivesBothTokens() public {
        _createAcceptAndSubmit();
        vm.prank(client); escrow.approveAndRelease(0);

        uint256 usdtJob     = 1_000e6;
        uint256 usdtDeposit = 1_060e6;
        vm.startPrank(client);
        usdt.approve(address(escrow), usdtDeposit);
        escrow.createJob(address(usdt), usdtJob, DEADLINE_SECS, "Design logo");
        vm.stopPrank();
        vm.prank(freelancer); escrow.acceptJob(1);
        vm.prank(freelancer); escrow.submitWork(1, WORK_LINK);
        vm.prank(client);     escrow.approveAndRelease(1);

        uint256 cNGNBefore = cNGN.balanceOf(owner);
        uint256 usdtBefore = usdt.balanceOf(owner);
        vm.startPrank(owner);
        escrow.withdrawFees(address(cNGN));
        escrow.withdrawFees(address(usdt));
        vm.stopPrank();
        assertGt(cNGN.balanceOf(owner), cNGNBefore);
        assertGt(usdt.balanceOf(owner), usdtBefore);
        assertEq(escrow.platformFeesAccumulated(address(cNGN)), 0);
        assertEq(escrow.platformFeesAccumulated(address(usdt)), 0);
    }

    function test_UpdateFees_success() public {
        vm.prank(owner);
        escrow.updateFees(500, 300);
        assertEq(escrow.clientFeeBps(),     500);
        assertEq(escrow.freelancerFeeBps(), 300);
    }

    // ── REVERT TESTS ────────────────────────────────────────────────────────

    function test_CreateJob_reverts_if_amountIsZero() public {
        vm.startPrank(client);
        cNGN.approve(address(escrow), 1_000e18);
        vm.expectRevert(FreelanceEscrow.InvalidAmount.selector);
        escrow.createJob(address(cNGN), 0, DEADLINE_SECS, "desc");
        vm.stopPrank();
    }

    function test_CreateJob_reverts_if_invalidToken() public {
        vm.startPrank(client);
        vm.expectRevert(FreelanceEscrow.InvalidToken.selector);
        escrow.createJob(address(0x123), JOB_AMOUNT, DEADLINE_SECS, "desc");
        vm.stopPrank();
    }

    function test_CreateJob_reverts_if_deadlineIsZero() public {
        vm.startPrank(client);
        cNGN.approve(address(escrow), CLIENT_DEPOSIT);
        vm.expectRevert(FreelanceEscrow.InvalidDeadline.selector);
        escrow.createJob(address(cNGN), JOB_AMOUNT, 0, "desc");
        vm.stopPrank();
    }

    function test_AcceptJob_reverts_if_notOpen() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(stranger);
        vm.expectRevert(FreelanceEscrow.JobNotOpen.selector);
        escrow.acceptJob(jobId);
    }

    function test_AcceptJob_reverts_if_clientIsFreelancer() public {
        uint256 jobId = _createJob();
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.ClientCannotBeFreelancer.selector);
        escrow.acceptJob(jobId);
    }

    function test_AcceptJob_reverts_if_deadlinePassed() public {
        uint256 jobId = _createJob();
        vm.warp(block.timestamp + DEADLINE_SECS + 1);
        vm.prank(freelancer);
        vm.expectRevert(FreelanceEscrow.InvalidDeadline.selector);
        escrow.acceptJob(jobId);
    }

    function test_SubmitWork_reverts_if_notFreelancer() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(stranger);
        vm.expectRevert(FreelanceEscrow.NotFreelancer.selector);
        escrow.submitWork(jobId, WORK_LINK);
    }

    function test_SubmitWork_reverts_if_notActive() public {
        uint256 jobId = _createJob();
        vm.prank(freelancer);
        vm.expectRevert(FreelanceEscrow.NotFreelancer.selector);
        escrow.submitWork(jobId, WORK_LINK);
    }

    function test_SubmitWork_reverts_if_emptyLink() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(freelancer);
        vm.expectRevert(FreelanceEscrow.EmptyWorkLink.selector);
        escrow.submitWork(jobId, "");
    }

    function test_ApproveAndRelease_reverts_if_notClient() public {
        uint256 jobId = _createAcceptAndSubmit();
        vm.prank(stranger);
        vm.expectRevert(FreelanceEscrow.NotClient.selector);
        escrow.approveAndRelease(jobId);
    }

    function test_ApproveAndRelease_reverts_if_notSubmitted() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.JobNotSubmitted.selector);
        escrow.approveAndRelease(jobId);
    }

    function test_ClaimPayment_reverts_if_deadlineNotReached() public {
        uint256 jobId = _createAcceptAndSubmit();
        vm.prank(freelancer);
        vm.expectRevert(FreelanceEscrow.DeadlineNotReached.selector);
        escrow.claimPayment(jobId);
    }

    function test_ClaimPayment_reverts_if_notFreelancer() public {
        uint256 jobId = _createAcceptAndSubmit();
        vm.warp(block.timestamp + DEADLINE_SECS + 1);
        vm.prank(stranger);
        vm.expectRevert(FreelanceEscrow.NotFreelancer.selector);
        escrow.claimPayment(jobId);
    }

    function test_ClaimRefund_reverts_if_deadlineNotReached() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.DeadlineNotReached.selector);
        escrow.claimRefund(jobId);
    }

    function test_ClaimRefund_reverts_if_notClient() public {
        uint256 jobId = _createAndAcceptJob();
        vm.warp(block.timestamp + DEADLINE_SECS + 1);
        vm.prank(stranger);
        vm.expectRevert(FreelanceEscrow.NotClient.selector);
        escrow.claimRefund(jobId);
    }

    function test_RaiseDispute_reverts_if_notSubmitted() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.JobNotSubmitted.selector);
        escrow.raiseDispute(jobId);
    }

    function test_RaiseDispute_reverts_if_alreadyRaised() public {
        uint256 jobId = _createAcceptAndSubmit();
        vm.prank(client); escrow.raiseDispute(jobId);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.JobNotSubmitted.selector);
        escrow.raiseDispute(jobId);
    }

    function test_ResolveDispute_reverts_if_notOwner() public {
        uint256 jobId = _createAcceptAndSubmit();
        vm.prank(client); escrow.raiseDispute(jobId);
        vm.prank(stranger);
        vm.expectRevert(FreelanceEscrow.NotPlatformOwner.selector);
        escrow.resolveDispute(jobId, 50);
    }

    function test_ResolveDispute_reverts_if_invalidSplit() public {
        uint256 jobId = _createAcceptAndSubmit();
        vm.prank(client); escrow.raiseDispute(jobId);
        vm.prank(owner);
        vm.expectRevert(FreelanceEscrow.InvalidSplit.selector);
        escrow.resolveDispute(jobId, 101);
    }

    function test_WithdrawFees_reverts_if_notOwner() public {
        vm.prank(stranger);
        vm.expectRevert(FreelanceEscrow.NotPlatformOwner.selector);
        escrow.withdrawFees(address(cNGN));
    }

    function test_WithdrawFees_reverts_if_noFees() public {
        vm.prank(owner);
        vm.expectRevert(FreelanceEscrow.NoFeesToWithdraw.selector);
        escrow.withdrawFees(address(cNGN));
    }

    function test_UpdateFees_reverts_if_tooHigh() public {
        vm.prank(owner);
        vm.expectRevert(FreelanceEscrow.FeeTooHigh.selector);
        escrow.updateFees(1000, 600);
    }

    function test_UpdateFees_reverts_if_notOwner() public {
        vm.prank(stranger);
        vm.expectRevert(FreelanceEscrow.NotPlatformOwner.selector);
        escrow.updateFees(500, 300);
    }
}
