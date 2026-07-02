// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title FreelanceEscrow
 * @author Solomon Abodunrin Adebayo
 * @notice NairaLance — Decentralized Freelance Escrow Platform
 * @dev Accepts cNGN and USDT. Platform fee: 6% client + 4% freelancer = 10% total.
 *      Job amount can be ANY value above zero. Work link accepts ANY URL format.
 */
contract FreelanceEscrow is Ownable, ReentrancyGuard {

    // ─────────────────────────────────────────────
    //  ENUMS
    // ─────────────────────────────────────────────

    enum JobStatus {
        Open,       // job posted, waiting for freelancer
        Active,     // freelancer accepted, work in progress
        Submitted,  // freelancer submitted work link
        Complete,   // payment released, job done
        Disputed,   // dispute raised, arbiter needed
        Refunded    // client refunded, job cancelled
    }

    // ─────────────────────────────────────────────
    //  STRUCTS
    // ─────────────────────────────────────────────

    struct Job {
        uint256 jobId;
        address client;
        address freelancer;
        uint256 jobAmount;       // agreed job price (any amount > 0)
        uint256 clientDeposit;   // jobAmount + 6% client fee
        IERC20 token;            // cNGN or USDT
        JobStatus status;
        uint256 deadline;        // unix timestamp
        string workLink;         // any URL: IPFS, GitHub, Drive, Figma, etc.
        string jobDescription;
    }

    // ─────────────────────────────────────────────
    //  STATE VARIABLES
    // ─────────────────────────────────────────────

    uint256 public jobCount;

    uint256 public clientFeeBps = 600;       // 6%
    uint256 public freelancerFeeBps = 400;   // 4%
    uint256 public constant MAX_FEE_BPS = 1500; // 15% safety cap (combined)

    // jobId => Job
    mapping(uint256 => Job) public jobs;

    // token => accumulated platform fees
    mapping(address => uint256) public platformFeesAccumulated;

    // whitelist of accepted tokens (cNGN, USDT)
    mapping(address => bool) public acceptedTokens;

    // ─────────────────────────────────────────────
    //  CUSTOM ERRORS
    // ─────────────────────────────────────────────

    error NotPlatformOwner();
    error NotClient();
    error NotFreelancer();
    error ClientCannotBeFreelancer();
    error JobNotOpen();
    error JobNotActive();
    error JobNotSubmitted();
    error JobNotDisputed();
    error InvalidAmount();
    error InvalidToken();
    error InvalidDeadline();
    error InvalidSplit();
    error EmptyWorkLink();
    error TransferFailed();
    error NoFeesToWithdraw();
    error DeadlineNotReached();
    error FeeTooHigh();

    // ─────────────────────────────────────────────
    //  EVENTS
    // ─────────────────────────────────────────────

    event JobCreated(
        uint256 indexed jobId,
        address indexed client,
        address indexed token,
        uint256 jobAmount,
        uint256 clientDeposit
    );

    event JobAccepted(uint256 indexed jobId, address indexed freelancer);

    event WorkSubmitted(uint256 indexed jobId, address indexed freelancer, string workLink);

    event JobApproved(uint256 indexed jobId, address indexed client, uint256 freelancerPayout);

    event PaymentClaimed(uint256 indexed jobId, address indexed freelancer, uint256 amount);

    event RefundClaimed(uint256 indexed jobId, address indexed client, uint256 amount);

    event DisputeRaised(uint256 indexed jobId, address indexed client);

    event DisputeResolved(
        uint256 indexed jobId,
        uint256 freelancerPercent,
        uint256 freelancerAmount,
        uint256 clientAmount
    );

    event FeesWithdrawn(address indexed token, address indexed owner, uint256 amount);

    event FeesUpdated(uint256 clientFeeBps, uint256 freelancerFeeBps);

    event TokenWhitelisted(address indexed token, bool accepted);

    // ─────────────────────────────────────────────
    //  MODIFIERS
    // ─────────────────────────────────────────────

    modifier onlyPlatformOwner() {
        if (msg.sender != owner()) revert NotPlatformOwner();
        _;
    }

    modifier onlyClient(uint256 jobId) {
        if (msg.sender != jobs[jobId].client) revert NotClient();
        _;
    }

    modifier onlyFreelancer(uint256 jobId) {
        if (msg.sender != jobs[jobId].freelancer) revert NotFreelancer();
        _;
    }

    // ─────────────────────────────────────────────
    //  CONSTRUCTOR
    // ─────────────────────────────────────────────

    constructor(address cNGN, address usdt) Ownable(msg.sender) {
        acceptedTokens[cNGN] = true;
        acceptedTokens[usdt] = true;
    }

    // ─────────────────────────────────────────────
    //  CLIENT FUNCTIONS
    // ─────────────────────────────────────────────

    /**
     * @notice Client posts a job and deposits jobAmount + 6% fee.
     * @param token Address of cNGN or USDT
     * @param jobAmount Any amount above zero — no minimum or maximum
     * @param deadlineInSeconds Duration from now until deadline
     * @param jobDescription Short description of the job
     */
    function createJob(
        address token,
        uint256 jobAmount,
        uint256 deadlineInSeconds,
        string calldata jobDescription
    ) external nonReentrant returns (uint256) {
        if (jobAmount == 0) revert InvalidAmount();
        if (!acceptedTokens[token]) revert InvalidToken();
        if (deadlineInSeconds == 0) revert InvalidDeadline();

        uint256 clientFee = (jobAmount * clientFeeBps) / 10000;
        uint256 clientDeposit = jobAmount + clientFee;

        uint256 jobId = jobCount++;

        jobs[jobId] = Job({
            jobId: jobId,
            client: msg.sender,
            freelancer: address(0),
            jobAmount: jobAmount,
            clientDeposit: clientDeposit,
            token: IERC20(token),
            status: JobStatus.Open,
            deadline: block.timestamp + deadlineInSeconds,
            workLink: "",
            jobDescription: jobDescription
        });

        emit JobCreated(jobId, msg.sender, token, jobAmount, clientDeposit);

        bool success = IERC20(token).transferFrom(msg.sender, address(this), clientDeposit);
        if (!success) revert TransferFailed();

        return jobId;
    }

    /**
     * @notice Client approves submitted work and releases payment to freelancer.
     */
    function approveAndRelease(uint256 jobId) external nonReentrant onlyClient(jobId) {
        Job storage job = jobs[jobId];

        if (job.status != JobStatus.Submitted) revert JobNotSubmitted();

        uint256 freelancerFee = (job.jobAmount * freelancerFeeBps) / 10000;
        uint256 freelancerPayout = job.jobAmount - freelancerFee;
        uint256 clientFee = job.clientDeposit - job.jobAmount;
        uint256 platformTotal = clientFee + freelancerFee;

        job.status = JobStatus.Complete;
        platformFeesAccumulated[address(job.token)] += platformTotal;

        emit JobApproved(jobId, msg.sender, freelancerPayout);

        bool success = job.token.transfer(job.freelancer, freelancerPayout);
        if (!success) revert TransferFailed();
    }

    /**
     * @notice Client claims full refund if freelancer never submitted work and deadline passed.
     */
    function claimRefund(uint256 jobId) external nonReentrant onlyClient(jobId) {
        Job storage job = jobs[jobId];

        if (job.status != JobStatus.Active && job.status != JobStatus.Open) revert JobNotActive();
        if (block.timestamp < job.deadline) revert DeadlineNotReached();

        uint256 refundAmount = job.clientDeposit;
        job.status = JobStatus.Refunded;

        emit RefundClaimed(jobId, msg.sender, refundAmount);

        bool success = job.token.transfer(job.client, refundAmount);
        if (!success) revert TransferFailed();
    }

    /**
     * @notice Client raises a dispute after work has been submitted.
     */
    function raiseDispute(uint256 jobId) external onlyClient(jobId) {
        Job storage job = jobs[jobId];

        if (job.status != JobStatus.Submitted) revert JobNotSubmitted();

        job.status = JobStatus.Disputed;

        emit DisputeRaised(jobId, msg.sender);
    }

    // ─────────────────────────────────────────────
    //  FREELANCER FUNCTIONS
    // ─────────────────────────────────────────────

    /**
     * @notice Freelancer accepts an open job.
     */
    function acceptJob(uint256 jobId) external {
        Job storage job = jobs[jobId];

        if (job.status != JobStatus.Open) revert JobNotOpen();
        if (msg.sender == job.client) revert ClientCannotBeFreelancer();
        if (block.timestamp > job.deadline) revert InvalidDeadline();

        job.freelancer = msg.sender;
        job.status = JobStatus.Active;

        emit JobAccepted(jobId, msg.sender);
    }

    /**
     * @notice Freelancer submits work — accepts ANY link format.
     * @param workLink Any URL: IPFS, GitHub, Google Drive, Figma, Notion, Dropbox, YouTube, etc.
     */
    function submitWork(uint256 jobId, string calldata workLink) external onlyFreelancer(jobId) {
        Job storage job = jobs[jobId];

        if (job.status != JobStatus.Active) revert JobNotActive();
        if (bytes(workLink).length == 0) revert EmptyWorkLink();

        job.workLink = workLink;
        job.status = JobStatus.Submitted;

        emit WorkSubmitted(jobId, msg.sender, workLink);
    }

    /**
     * @notice Freelancer claims payment automatically if client ghosts past deadline.
     */
    function claimPayment(uint256 jobId) external nonReentrant onlyFreelancer(jobId) {
        Job storage job = jobs[jobId];

        if (job.status != JobStatus.Submitted) revert JobNotSubmitted();
        if (block.timestamp < job.deadline) revert DeadlineNotReached();

        uint256 freelancerFee = (job.jobAmount * freelancerFeeBps) / 10000;
        uint256 freelancerPayout = job.jobAmount - freelancerFee;
        uint256 clientFee = job.clientDeposit - job.jobAmount;
        uint256 platformTotal = clientFee + freelancerFee;

        job.status = JobStatus.Complete;
        platformFeesAccumulated[address(job.token)] += platformTotal;

        emit PaymentClaimed(jobId, msg.sender, freelancerPayout);

        bool success = job.token.transfer(job.freelancer, freelancerPayout);
        if (!success) revert TransferFailed();
    }

    // ─────────────────────────────────────────────
    //  ARBITER (OWNER) FUNCTIONS
    // ─────────────────────────────────────────────

    /**
     * @notice Owner resolves a dispute by splitting funds between freelancer and client.
     * @param freelancerPercent Percentage (0-100) of remaining funds that goes to freelancer
     */
    function resolveDispute(uint256 jobId, uint256 freelancerPercent) external nonReentrant onlyPlatformOwner {
        Job storage job = jobs[jobId];

        if (job.status != JobStatus.Disputed) revert JobNotDisputed();
        if (freelancerPercent > 100) revert InvalidSplit();

        uint256 freelancerFee = (job.jobAmount * freelancerFeeBps) / 10000;
        uint256 clientFee = job.clientDeposit - job.jobAmount;
        uint256 platformTotal = clientFee + freelancerFee;

        uint256 remaining = job.jobAmount - freelancerFee;
        uint256 freelancerAmount = (remaining * freelancerPercent) / 100;
        uint256 clientAmount = remaining - freelancerAmount;

        job.status = JobStatus.Complete;
        platformFeesAccumulated[address(job.token)] += platformTotal;

        emit DisputeResolved(jobId, freelancerPercent, freelancerAmount, clientAmount);

        if (freelancerAmount > 0) {
            bool successFreelancer = job.token.transfer(job.freelancer, freelancerAmount);
            if (!successFreelancer) revert TransferFailed();
        }

        if (clientAmount > 0) {
            bool successClient = job.token.transfer(job.client, clientAmount);
            if (!successClient) revert TransferFailed();
        }
    }

    /**
     * @notice Owner withdraws accumulated platform fees for a given token.
     */
    function withdrawFees(address token) external nonReentrant onlyPlatformOwner {
        uint256 amount = platformFeesAccumulated[token];
        if (amount == 0) revert NoFeesToWithdraw();

        platformFeesAccumulated[token] = 0;

        emit FeesWithdrawn(token, msg.sender, amount);

        bool success = IERC20(token).transfer(msg.sender, amount);
        if (!success) revert TransferFailed();
    }

    /**
     * @notice Owner updates the fee structure. Combined fee capped at MAX_FEE_BPS.
     */
    function updateFees(uint256 newClientFeeBps, uint256 newFreelancerFeeBps) external onlyPlatformOwner {
        if (newClientFeeBps + newFreelancerFeeBps > MAX_FEE_BPS) revert FeeTooHigh();

        clientFeeBps = newClientFeeBps;
        freelancerFeeBps = newFreelancerFeeBps;

        emit FeesUpdated(newClientFeeBps, newFreelancerFeeBps);
    }

    /**
     * @notice Owner adds or removes a token from the accepted whitelist.
     */
    function setAcceptedToken(address token, bool accepted) external onlyPlatformOwner {
        acceptedTokens[token] = accepted;
        emit TokenWhitelisted(token, accepted);
    }

    // ─────────────────────────────────────────────
    //  VIEW FUNCTIONS
    // ─────────────────────────────────────────────

    function getJob(uint256 jobId) external view returns (Job memory) {
        return jobs[jobId];
    }

    function getWorkLink(uint256 jobId) external view returns (string memory) {
        return jobs[jobId].workLink;
    }
}
