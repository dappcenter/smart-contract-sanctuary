// SPDX-License-Identifier: ISC

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/**
 * @title ERC721
 * @dev Abstract base implementation for ERC721 functions utilized within dispensary contract.
 */
abstract contract ERC721 {
    function ownerOf(uint256 id) public virtual returns (address owner);

    function balanceOf(address owner) public virtual returns (uint256 balance);

    function tokenOfOwnerByIndex(address owner, uint256 index) public virtual returns (uint256 id);
}

/**
 * @title ERC20
 * @dev Abstract base implementation for ERC20 functions utilized within dispensary contract.
 */
abstract contract ERC20 {
    function transfer(address to, uint256 value) public virtual;
}


/**
 * @title BohoTokenDispensary
 * @dev Responsible for oversight of dispensed $BOHO tokens for BOHOBONES holders.
 */
contract BohoTokenDispensary is Ownable {
    using SafeMath for uint256;

    // Mapping to keep track of token claims
    mapping(uint256 => bool) bohoClaims;

    // Variables for Bones ERC721 and Boho ERC20 contracts 
    ERC721 public bonesContract;
    ERC20 public bohoContract;

    // Bool to pause/unpause dispenser
    bool public isActive = false;

    // Dispense amount
    uint256 public amount = 7777 * 1 ether;

    /**
     * @param amount Amount dispensed.
     * @param bonesId Bones token ID for the given claim.
     */
    event Dispense(uint256 amount, uint256 bonesId);

    // Constructor
    constructor(address bonesContractAddress, address bohoContractAddress) {
        // Load ERC721 and ERC20 contracts
        bonesContract = ERC721(bonesContractAddress);
        bohoContract = ERC20(bohoContractAddress);
    }

    /**
     * Prevents a function from running if contract is paused
     */
    modifier dispensaryIsActive() {
        require(isActive == true, "BohoTokenClaim: Contract is paused.");
        _;
    }

    /**
     * @param bonesId ID of the Bohemian Bone checking claimed $BOHO status for.
     * Prevents repeat claims for a given Bohemian Bone.
     */
    modifier isNotClaimed(uint256 bonesId) {
        bool claimed = isClaimed(bonesId);
        require(claimed == false, "BohoTokenClaim: Tokens for this Bohemian have already been claimed!");
        _;
    }

    /**
     * @param newBonesContractAddress Address of the new ERC721 contract.
     * @dev Sets the address for the referenced Bohemian Bone ERC721 contract.
     * @dev Can only be called by contract owner.
     */
    function setBonesContractAddress(address newBonesContractAddress) public onlyOwner {
        bonesContract = ERC721(newBonesContractAddress);
    }

    /**
     * @param newBohoContractAddress Address of the new ERC20 contract.
     * @dev Sets the address for the referenced $BOHO ERC20 contract.
     * @dev Can only be called by contract owner.
     */
    function setBohoContractAddress(address newBohoContractAddress) public onlyOwner {
        bohoContract = ERC20(newBohoContractAddress);
    }
    
    /**
     * @param bonesId ID of the Bohemian Bone we are checking claimed status for.
     * @dev Returns a boolean indicating if $BOHO have been claimed for this Bohemian Bone.
     */
    function isClaimed(uint256 bonesId) public view returns (bool) {
        return bohoClaims[bonesId];
    }

    /**
     * @dev Sets the dispensary to unpaused if paused, and paused if unpaused.
     * @dev Can only be called by contract owner.
     */
    function flipDispensaryState() public onlyOwner {
        isActive = !isActive;
    }

    /**
     * @param newAmount The new amount $BOHO to dispense per claim.
     * @dev Changes the amount of $BOHO handed out per claim.
     * @dev Can only be called by contract owner.
     */
    function setAmount(uint256 newAmount) public onlyOwner {
        amount = newAmount;
    }

    /**
     * @param withdrawAmount Amount of $BOHO to withdraw into dispensary contract.
     * @dev Provides method for withdrawing $BOHO from contract, if necessary.
     * @dev Can only be called by contract owner.
     */
    function withdraw(uint256 withdrawAmount) public onlyOwner dispensaryIsActive {
        bohoContract.transfer(msg.sender, withdrawAmount);
    }

    /**
     * @param bonesId ID of the Bohemian Bone to claim $BOHO for.
     * @dev Claims the $BOHO for the given Bohemian Bone ID.
     * @dev Can only be called when dispensary is active.
     * @dev Cannot be called again once a claim has already been made for the given ID.
     */
    function claimBoho(uint256 bonesId) public dispensaryIsActive isNotClaimed(bonesId) {
        address bohoOwner = bonesContract.ownerOf(bonesId);
        require(msg.sender == bohoOwner, 'caller is not owner of this boho');

        bohoClaims[bonesId] = true;
        // bohoContract.transfer(msg.sender, amount);

        // emit Dispense(amount, bonesId);
    }


    /**
     * @param bonesIds IDs of the Bohemian Bones to claim $BOHO for.
     * @dev Claims the $BOHO for the given list of Bohemian Bone IDs.
     * @dev Can only be called when dispensary is active.
     */
    function multiClaimBoho(uint256[] memory bonesIds) public dispensaryIsActive {
        for (uint256 i = 0; i < bonesIds.length; i++) {
            bool claimed = isClaimed(bonesIds[i]);
            if (!claimed) claimBoho(bonesIds[i]);
        }
    }

    /**
     * @dev Claims the $BOHO for all Bohemian Bone IDs owned by caller.
     * @dev Can only be called when dispensary is active.
     */
    function megaClaimBoho() public dispensaryIsActive {
        uint256 bohoBalance = bonesContract.balanceOf(msg.sender);
        for (uint256 i = 0; i < bohoBalance; i++) {
            uint256 tokenId = bonesContract.tokenOfOwnerByIndex(msg.sender, i);
            bool claimed = isClaimed(tokenId);
            if (!claimed) claimBoho(tokenId);
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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
    constructor () internal {
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

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        uint256 c = a + b;
        if (c < a) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b > a) return (false, 0);
        return (true, a - b);
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) return (true, 0);
        uint256 c = a * b;
        if (c / a != b) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a / b);
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a % b);
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: modulo by zero");
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        return a - b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryDiv}.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a % b;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

{
  "optimizer": {
    "enabled": true,
    "runs": 500
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