pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./BlocksStaking.sol";


contract BlocksRewardsManager is Ownable {
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many blocks user owns currently.
        uint256 pendingRewards; // Rewards assigned, but not yet claimed
        uint256 rewardsDebt;
    }

    // Info of each blocks.space
    struct SpaceInfo {
        uint256 spaceId;
        uint256 amountOfBlocksBought; // Number of all blocks bought on this space
        address contractAddress; // Address of space contract.
        uint256 blsPerBlockAreaPerBlock; // Start with 830000000000000 wei (approx 24 BLS/block.area/day)
        uint256 blsRewardsAcc;
        uint256 blsRewardsAccLastUpdated;
    }

    // Management of splitting rewards
    uint256 constant MAX_TREASURY_FEE = 5;
    uint256 constant MAX_LIQUIDITY_FEE = 10;
    uint256 constant MAX_PREVIOUS_OWNER_FEE = 50;
    uint256 public treasuryFee = 5;
    uint256 public liquidityFee = 10;
    uint256 public previousOwnerFee = 25;

    address payable public treasury;
    IERC20 public blsToken;
    BlocksStaking public blocksStaking;
    SpaceInfo[] public spaceInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(address => bool) public spacesByAddress;
    // Variables that support calculation of proper bls rewards distributions
    uint256 public blsPerBlock;
    uint256 public blsLastRewardsBlock;
    uint256 public blsSpacesRewardsDebt; // bls rewards debt accumulated
    uint256 public blsSpacesDebtLastUpdatedBlock;
    uint256 public blsSpacesRewardsClaimed;

    event SpaceAdded(uint256 indexed spaceId, address indexed space, address indexed addedBy);
    event Claim(address indexed user, uint256 amount);
    event BlsPerBlockAreaPerBlockUpdated(uint256 spaceId, uint256 newAmount);
    event TreasuryFeeSet(uint256 newFee);
    event LiquidityFeeSet(uint256 newFee);
    event PreviousOwnerFeeSet(uint256 newFee);
    event BlocksStakingContractUpdated(address add);
    event TreasuryWalletUpdated(address newWallet);
    event BlsRewardsForDistributionDeposited(uint256 amount);

    modifier onlySpace() {
        require(spacesByAddress[msg.sender] == true, "Not a space.");
        _;
    }

    constructor(IERC20 blsAddress_, address blocksStakingAddress_, address treasury_) {
        blsToken = IERC20(blsAddress_);
        blocksStaking = BlocksStaking(blocksStakingAddress_);
        treasury = payable(treasury_);
    }

    function spacesLength() external view returns (uint256) {
        return spaceInfo.length;
    }

    function addSpace(address spaceContract_, uint256 blsPerBlockAreaPerBlock_) external onlyOwner {
        spacesByAddress[spaceContract_] = true;
        uint256 spaceId = spaceInfo.length;
        SpaceInfo storage newSpace = spaceInfo.push();
        newSpace.contractAddress = spaceContract_;
        newSpace.spaceId = spaceId;
        newSpace.blsPerBlockAreaPerBlock = blsPerBlockAreaPerBlock_;
        emit SpaceAdded(spaceId, spaceContract_, msg.sender);
    }

    function updateBlsPerBlockAreaPerBlock(uint256 spaceId_, uint256 newAmount_) external onlyOwner {
        SpaceInfo storage space = spaceInfo[spaceId_];
        require(space.contractAddress != address(0), "SpaceInfo does not exist");

        massUpdateSpaces();

        uint256 oldSpaceBlsPerBlock = space.blsPerBlockAreaPerBlock * space.amountOfBlocksBought;
        uint256 newSpaceBlsPerBlock = newAmount_ * space.amountOfBlocksBought;
        blsPerBlock = blsPerBlock + newSpaceBlsPerBlock - oldSpaceBlsPerBlock;
        space.blsPerBlockAreaPerBlock = newAmount_;
        
        recalculateLastRewardBlock();
        emit BlsPerBlockAreaPerBlockUpdated(spaceId_, newAmount_);
    }

    function pendingBlsTokens(uint256 spaceId_, address user_) public view returns (uint256) {
        SpaceInfo storage space = spaceInfo[spaceId_];
        UserInfo storage user = userInfo[spaceId_][user_];
        uint256 rewards;
        if (user.amount > 0 && space.blsRewardsAccLastUpdated < block.number) {
            uint256 multiplier = getMultiplier(space.blsRewardsAccLastUpdated);
            uint256 blsRewards = multiplier * space.blsPerBlockAreaPerBlock;
            rewards = user.amount * blsRewards;
        }
        return user.amount * space.blsRewardsAcc + rewards + user.pendingRewards - user.rewardsDebt;
    }

    function getMultiplier(uint256 usersLastRewardsCalculatedBlock) internal view returns (uint256) {
        if (block.number > blsLastRewardsBlock) {           
            if(blsLastRewardsBlock >= usersLastRewardsCalculatedBlock){
                return blsLastRewardsBlock - usersLastRewardsCalculatedBlock;
            }else{
                return 0;
            }
        } else {
            return block.number - usersLastRewardsCalculatedBlock;  
        }
    }

    function massUpdateSpaces() public {
        uint256 length = spaceInfo.length;
        for (uint256 spaceId = 0; spaceId < length; ++spaceId) {
            updateSpace(spaceId);
        }
        
        if(block.number > blsLastRewardsBlock){
            blsSpacesRewardsDebt = blsSpacesRewardsDebt + (blsLastRewardsBlock - blsSpacesDebtLastUpdatedBlock) * blsPerBlock;   
        }else{ // We are adding BLS rewards still when old ones did not run out
            blsSpacesRewardsDebt = blsSpacesRewardsDebt + (block.number - blsSpacesDebtLastUpdatedBlock) * blsPerBlock;
        }
        blsSpacesDebtLastUpdatedBlock = block.number;
    }

    function updateSpace(uint256 spaceId_) internal {
        // If space was not yet updated, update rewards accumulated
        SpaceInfo storage space = spaceInfo[spaceId_];
        if (block.number <= space.blsRewardsAccLastUpdated) {
            return;
        }
        if (space.amountOfBlocksBought == 0) {
            space.blsRewardsAccLastUpdated = block.number;
            return;
        }
        if (block.number > space.blsRewardsAccLastUpdated) {
            uint256 multiplierSpace = getMultiplier(space.blsRewardsAccLastUpdated);
            space.blsRewardsAcc = space.blsRewardsAcc + multiplierSpace * space.blsPerBlockAreaPerBlock;
            space.blsRewardsAccLastUpdated = block.number;
        }
    }

    function blocksAreaBoughtOnSpace(
        uint256 spaceId_,
        address buyer_,
        address[] calldata previousBlockOwners_,
        uint256[] calldata previousOwnersPrices_
    ) public payable onlySpace {
        
        updateSpace(spaceId_);

        SpaceInfo storage space = spaceInfo[spaceId_];
        UserInfo storage user = userInfo[spaceId_][buyer_];
        uint256 spaceBlsRewardsAcc = space.blsRewardsAcc;

        // If user already had some block.areas then calculate all rewards pending
        if (user.amount > 0) {
            user.pendingRewards = user.pendingRewards + user.amount * spaceBlsRewardsAcc;  
        }
        uint256 numberOfBlocksBought = previousBlockOwners_.length;
        // Set user data
        user.amount = user.amount + numberOfBlocksBought;
        // user.rewardsDebt = user.amount * spaceBlsRewardsAcc;
        user.rewardsDebt = user.rewardsDebt + user.amount * spaceBlsRewardsAcc; // TODO: check if this is right

        //remove blocks from previous owners that this guy took over. Max 42 loops
        uint256 allPreviousOwnersPaid;
        uint256 numberOfBlocksToRemove;
        for (uint256 i = 0; i < numberOfBlocksBought; ++i) {
            // If previous owners of block are non zero address, means we need to take block from them
            if (previousBlockOwners_[i] != address(0)) {
                allPreviousOwnersPaid = allPreviousOwnersPaid + previousOwnersPrices_[i];
                // Calculate previous users pending BLS rewards
                UserInfo storage prevUser = userInfo[spaceId_][previousBlockOwners_[i]];
                prevUser.pendingRewards = prevUser.pendingRewards + spaceBlsRewardsAcc;
                // Remove his ownership of block
                --prevUser.amount;
                ++numberOfBlocksToRemove;
            }
        }
        uint256 numberOfBlocksAdded = numberOfBlocksBought - numberOfBlocksToRemove;
        // If amount of blocks on space changed, we need to update space and global state
        if (numberOfBlocksAdded > 0) {
            blsSpacesRewardsDebt = blsSpacesRewardsDebt + (block.number - blsSpacesDebtLastUpdatedBlock) * blsPerBlock;
            blsSpacesDebtLastUpdatedBlock = block.number;

            blsPerBlock = blsPerBlock + space.blsPerBlockAreaPerBlock * numberOfBlocksAdded;
            space.amountOfBlocksBought = space.amountOfBlocksBought + numberOfBlocksAdded;

            // Recalculate what is last block eligible for BLS rewards
            uint256 blsBalance = blsToken.balanceOf(address(this));
            // If this is true, we are still in state of distribution of rewards
            if (blsBalance > blsSpacesRewardsDebt) {
                uint256 blocksTillBlsRunOut = (blsBalance + blsSpacesRewardsClaimed - blsSpacesRewardsDebt) / blsPerBlock;
                blsLastRewardsBlock = block.number + blocksTillBlsRunOut;
            }
        }

        // Calculate and subtract fees in first part
        // In second part, calculate how much rewards are being rewarded to previous block owners
        (uint256 rewardToForward, uint256[] memory prevOwnersRewards) = calculateAndDistributeFees(
            msg.value,
            previousOwnersPrices_,
            allPreviousOwnersPaid
        );

        // Send to distribution part
        blocksStaking.distributeRewards{value: rewardToForward}(previousBlockOwners_, prevOwnersRewards);
    }

    function calculateAndDistributeFees(
        uint256 rewardReceived_,
        uint256[] calldata previousOwnersPrices_,
        uint256 previousOwnersPaid_
    ) internal returns (uint256, uint256[] memory) {
        uint256 numberOfBlocks = previousOwnersPrices_.length;
        uint256 feesTaken;
        uint256 previousOwnersFeeValue;
        uint256[] memory previousOwnersRewardWei = new uint256[](numberOfBlocks);
        if (previousOwnerFee > 0 && previousOwnersPaid_ != 0) {
            previousOwnersFeeValue = (rewardReceived_ * previousOwnerFee) / 100; // Calculate how much is for example 25% of whole rewards gathered
            uint256 onePartForPreviousOwners = (previousOwnersFeeValue * 1e9) / previousOwnersPaid_; // Then calculate one part for previous owners sum
            for (uint256 i = 0; i < numberOfBlocks; ++i) {
                // Now we calculate exactly how much one user gets depending on his investment (it needs to be proportionally)
                previousOwnersRewardWei[i] = (onePartForPreviousOwners * previousOwnersPrices_[i]) / 1e9;
            }
        }
        // Can be max 5%
        if (treasuryFee > 0) {
            uint256 treasuryFeeValue = (rewardReceived_ * treasuryFee) / 100;
            if (treasuryFeeValue > 0) {
                feesTaken = feesTaken + treasuryFeeValue;
            }
        }
        // Can be max 10%
        if (liquidityFee > 0) {
            uint256 liquidityFeeValue = (rewardReceived_ * liquidityFee) / 100;
            if (liquidityFeeValue > 0) {
                feesTaken = feesTaken + liquidityFeeValue;
            }
        }
        // Send fees to treasury. Max together 15%. We use call, because it enables auto liqudity provisioning on DEX in future when token is trading
        if (feesTaken > 0) {
            (bool sent,) = treasury.call{value: feesTaken}("");
            require(sent, "Failed to send Ether");
        }

        return (rewardReceived_ - feesTaken, previousOwnersRewardWei);
    }

    function claim(uint256 spaceId_) public {
        UserInfo storage user = userInfo[spaceId_][msg.sender];
        uint256 toClaimAmount = pendingBlsTokens(spaceId_, msg.sender);
        if (toClaimAmount > 0) {
            uint256 claimedAmount = safeBlsTransfer(msg.sender, toClaimAmount);
            emit Claim(msg.sender, claimedAmount);
            // This is also kinda check, since if user claims more than eligible, this will revert
            user.pendingRewards = toClaimAmount - claimedAmount;
            user.rewardsDebt = spaceInfo[spaceId_].blsRewardsAcc * user.amount + claimedAmount;
            blsSpacesRewardsClaimed = blsSpacesRewardsClaimed + claimedAmount; // Globally claimed rewards, for proper end distribution calc
        }
    }

    // Safe BLS transfer function, just in case if rounding error causes pool to not have enough BLSs.
    function safeBlsTransfer(address to_, uint256 amount_) internal returns (uint256) {
        uint256 blsBalance = blsToken.balanceOf(address(this));
        if (amount_ > blsBalance) {
            blsToken.transfer(to_, blsBalance);
            return blsBalance;
        } else {
            blsToken.transfer(to_, amount_);
            return amount_;
        }
    }

    function setTreasuryFee(uint256 newFee_) external onlyOwner {
        require(newFee_ <= MAX_TREASURY_FEE);
        treasuryFee = newFee_;
        emit TreasuryFeeSet(newFee_);
    }

    function setLiquidityFee(uint256 newFee_) external onlyOwner {
        require(newFee_ <= MAX_LIQUIDITY_FEE);
        liquidityFee = newFee_;
        emit LiquidityFeeSet(newFee_);
    }

    function setPreviousOwnerFee(uint256 newFee_) external onlyOwner {
        require(newFee_ <= MAX_PREVIOUS_OWNER_FEE);
        previousOwnerFee = newFee_;
        emit PreviousOwnerFeeSet(newFee_);
    }

    function updateBlocksStakingContract(address address_) external onlyOwner {
        blocksStaking = BlocksStaking(address_);
        emit BlocksStakingContractUpdated(address_);
    }

    function updateTreasuryWallet(address newWallet_) external onlyOwner {
        treasury = payable(newWallet_);
        emit TreasuryWalletUpdated(newWallet_);
    }

    function depositBlsRewardsForDistribution(uint256 amount_) external onlyOwner {
        blsToken.transferFrom(address(msg.sender), address(this), amount_);

        massUpdateSpaces();
        recalculateLastRewardBlock();

        emit BlsRewardsForDistributionDeposited(amount_);    
    }

    function recalculateLastRewardBlock() internal {
        uint256 blsBalance = blsToken.balanceOf(address(this));
        if (blsBalance >= blsSpacesRewardsDebt && blsPerBlock > 0) {
            uint256 blocksTillBlsRunOut = (blsBalance + blsSpacesRewardsClaimed - blsSpacesRewardsDebt) / blsPerBlock;
            blsLastRewardsBlock = block.number + blocksTillBlsRunOut;
        }
    }

}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/Context.sol";
/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @dev This contract implements the logic for staking BLS amount. It
 * also handles BNB rewards distribution to users for their blocks taken
 * over (that got covered) and rewards for staked BLS amount.
 */
contract BlocksStaking is Ownable {
    using SafeERC20 for IERC20;

    // Object with information for a user
    struct UserInfo {
        uint256 amount; // Amount of amount being staked
        uint256 rewardDebt;
        uint256 takeoverReward; // Reward for covered blocks
    }

    uint256 public rewardsDistributionPeriod = 42 days / 3; // How long are we distributing incoming rewards

    // Global staking variables
    uint256 public totalTokens; // Total amount of amount currently staked
    uint256 public rewardsPerBlock; // Multiplied by 1e12 for better division precision
    uint256 public rewardsFinishedBlock; // When will rewards distribution end
    uint256 accRewardsPerShare; // Accumulated rewards per share
    uint256 lastRewardCalculatedBlock; // Last time we calculated accumulation of rewards per share
    uint256 allUsersRewardDebt; // Helper to keep track of proper account balance for distribution
    uint256 takeoverRewards; // Helper to keep track of proper account balance for distribution

    // Mapping of UserInfo object to a wallet
    mapping(address => UserInfo) public userInfo;

    // The BLS token contract
    IERC20 private blsToken;

    // Event that is triggered when a user claims his rewards
    event Claim(address indexed user, uint256 reward);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event RewardDistributionPeriodSet(uint256 period);

    /**
     * @dev Provides addresses for BLS token contract
     */
    constructor(IERC20 blsTokenAddress_) {
        blsToken = IERC20(blsTokenAddress_);
    }

    function setRewardDistributionPeriod(uint256 period_) external onlyOwner {
        rewardsDistributionPeriod = period_;
        emit RewardDistributionPeriodSet(period_);
    }

    // View function to see pending BLSs on frontend.
    function pendingRewards(address user_) public view returns (uint256) {
        UserInfo storage user = userInfo[user_];
        uint256 tempAccRewardsPerShare = accRewardsPerShare;
        if (user.amount > 0) {
            tempAccRewardsPerShare = tempAccRewardsPerShare + (rewardsPerBlock * getMultiplier()) / totalTokens;
        }
        return ((tempAccRewardsPerShare * user.amount) / 1e12) + user.takeoverReward - user.rewardDebt;
    }

    // View function for showing rewards counter on frontend. Its multiplied by 1e12
    function rewardsPerBlockPerToken() external view returns(uint256) {
        if (block.number > rewardsFinishedBlock || totalTokens <= 0) {
            return 0;
        } else {
            return rewardsPerBlock / totalTokens;
        }
    }

    function getMultiplier() internal view returns (uint256) {
        // if (block.number > rewardsFinishedBlock && rewardsFinishedBlock >= lastRewardCalculatedBlock) {
        //     return rewardsFinishedBlock - lastRewardCalculatedBlock;
        // } else {
        //     return block.number - lastRewardCalculatedBlock;
        // }
        if (block.number > rewardsFinishedBlock) {
            if(rewardsFinishedBlock >= lastRewardCalculatedBlock){
                return rewardsFinishedBlock - lastRewardCalculatedBlock;
            }else{
                return 0;
            }
        }else{
            return block.number - lastRewardCalculatedBlock;
        }
    }

    /**
     * @dev The user deposits BLS amount for staking.
     */
    function deposit(uint256 amount_) public {
        UserInfo storage user = userInfo[msg.sender];
        // if there are staked amount, fully harvest current reward
        if (user.amount > 0) {
            claim();
        }

        if (totalTokens > 0) {
            accRewardsPerShare = accRewardsPerShare + (rewardsPerBlock * getMultiplier()) / totalTokens;
        } else {
            calculateRewardsDistribution(); // Means first time any user deposits, so start distributing
        }

        lastRewardCalculatedBlock = block.number;

        totalTokens = totalTokens + amount_; // sum of total staked amount
        user.amount = user.amount + amount_; // cache staked amount count for this wallet
        user.rewardDebt = (accRewardsPerShare * user.amount) / 1e12; // cache current total reward per token
        allUsersRewardDebt = allUsersRewardDebt + (accRewardsPerShare * user.amount) / 1e12;
        emit Deposit(msg.sender, amount_);
        // Transfer BLS amount from the user to this contract
        blsToken.safeTransferFrom(address(msg.sender), address(this), amount_);
    }

    /**
     * @dev The user withdraws staked BLS amount and claims the rewards.
     */
    function withdraw() public {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;
        require(amount > 0, "No amount deposited for withdrawal.");
        // Claim any available rewards
        claim();

        // Update rewards per share because total tokens change
        accRewardsPerShare = accRewardsPerShare + (rewardsPerBlock * getMultiplier()) / totalTokens;
        lastRewardCalculatedBlock = block.number;

        totalTokens = totalTokens - amount;
        user.amount = 0;
        user.rewardDebt = 0;

        // Transfer BLS amount from this contract to the user
        uint256 amountWithdrawn = safeBlsTransfer(address(msg.sender), amount);
        emit Withdraw(msg.sender, amountWithdrawn);
    }

    /**
     * @dev The user just withdraws staked BLS amount and leaves any rewards.
     */
    function emergencyWithdraw() public {
        UserInfo storage user = userInfo[msg.sender];

        user.amount = 0;
        user.rewardDebt = 0;

        // Transfer BLS amount from this contract to the user
        uint256 amountWithdrawn = safeBlsTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, amountWithdrawn);
    }

    /**
     * @dev Claim rewards from staking and covered blocks.
     */
    function claim() public {
        uint256 reward = pendingRewards(msg.sender);

        if (reward <= 0) return; // skip if no rewards

        UserInfo storage user = userInfo[msg.sender];
        takeoverRewards = takeoverRewards - user.takeoverReward;
        user.rewardDebt = 0; // reset: cache current total reward per token
        user.takeoverReward = 0; // reset takeover reward

        // transfer reward in BNBs to the user
        (bool success, ) = msg.sender.call{value: reward}("");
        require(success, "Transfer failed.");
        emit Claim(msg.sender, reward);
    }

    /**
     * @dev Distribute rewards for covered blocks, what remains goes for staked amount.
     */
    function distributeRewards(address[] calldata addresses_, uint256[] calldata rewards_) public payable {
        uint256 tmpTakeoverRewards;
        for (uint256 i = 0; i < addresses_.length; ++i) {
            // process each reward for covered blocks
            userInfo[addresses_[i]].takeoverReward = userInfo[addresses_[i]].takeoverReward + rewards_[i]; // each user that got blocks covered gets a reward
            tmpTakeoverRewards = tmpTakeoverRewards + rewards_[i];
        }
        takeoverRewards = takeoverRewards + tmpTakeoverRewards;

        // what remains is the reward for staked amount
        if (msg.value - tmpTakeoverRewards > 0 && totalTokens > 0) {
            // Update rewards per share because balance changes
            accRewardsPerShare = accRewardsPerShare + (rewardsPerBlock * getMultiplier()) / totalTokens;
            lastRewardCalculatedBlock = block.number;
            calculateRewardsDistribution();
        }
    }

    function calculateRewardsDistribution() internal {
        uint256 allReservedRewards = (accRewardsPerShare * totalTokens) / 1e12;
        uint256 availableForDistribution = (address(this).balance + allUsersRewardDebt - allReservedRewards - takeoverRewards);
        rewardsPerBlock = (availableForDistribution * 1e12) / rewardsDistributionPeriod;
        rewardsFinishedBlock = block.number + rewardsDistributionPeriod;
    }

    /**
     * @dev Safe BLS transfer function in case of a rounding error. If not enough amount in the contract, trensfer all of them.
     */
    function safeBlsTransfer(address to_, uint256 amount_) internal returns (uint256) {
        uint256 blsBalance = blsToken.balanceOf(address(this));
        if (amount_ > blsBalance) {
            blsToken.transfer(to_, blsBalance);
            return blsBalance;
        } else {
            blsToken.transfer(to_, amount_);
            return amount_;
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC20.sol";
import "../../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

{
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "outputSelection": {
    "*": {
      "*": [
        "evm.bytecode",
        "evm.deployedBytecode",
        "abi"
      ]
    }
  },
  "libraries": {}
}