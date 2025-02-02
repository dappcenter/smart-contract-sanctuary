pragma solidity ^0.6.12;
// SPDX-License-Identifier: Unlicensed

contract TeamLeadAirdrops  {

	using SafeMath for uint256;
		
		//address[] public receivers;
		//uint256[] public amounts;
		
	iMoonCoin public MoonCoinApp;
	iMoonCoin public MoonCoinAirApp;
	iMoonCoin public SafemoonApp;
	
	address payable public platformAddress;
	//event AirdropSummary(uint256 totalUser, uint256 totalSent, uint256 totalCost);
	//event AirdropSent(address indexed from, address indexed to, uint256 value);

	constructor( iMoonCoin _MoonCoin, iMoonCoin _MoonCoinAir, iMoonCoin _Safemoon) public { 
		platformAddress=msg.sender;	
		MoonCoinApp = _MoonCoin;
		MoonCoinAirApp = _MoonCoinAir;
		SafemoonApp = _Safemoon;
	}
	  receive() external payable {}
	  
	function getChainID() public pure returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }
	
	
	
		function multiSendMoonCoin(address[] memory _receivers, uint256[] memory _amounts, uint256 _totalCost) public {
			MoonCoinApp.transferFrom(msg.sender, address(this), _totalCost); 		
			for (uint256 i = 0; i < _receivers.length; ++i) {				
				MoonCoinApp.transfer(_receivers[i], _amounts[i]);
			}
		}
	
function multiSendMoonCoinAir(address[] memory _receivers, uint256[] memory _amounts, uint256 _totalCost) public {
			MoonCoinAirApp.transferFrom(msg.sender, address(this), _totalCost); 		
			for (uint256 i = 0; i < _receivers.length; ++i) {				
				MoonCoinAirApp.transfer(_receivers[i], _amounts[i]);
			}
		}
	
	function multiSendSafemoon(address[] memory _receivers, uint256[] memory _amounts, uint256 _totalCost) public {
			SafemoonApp.transferFrom(msg.sender, address(this), _totalCost); 		
			for (uint256 i = 0; i < _receivers.length; ++i) {				
				SafemoonApp.transfer(_receivers[i], _amounts[i]);
			}
		}
		
		
	
	function getRemainingMoons() public { 	// TBA	
		require(msg.sender == platformAddress, "1");
		MoonCoinApp.transfer(msg.sender, MoonCoinApp.balanceOf(address(this)));		
	} 


function recoverLostBNB() public  {
        require(msg.sender == platformAddress, "1");
		address payable owner = msg.sender;
        owner.transfer(address(this).balance);
    }	

	
	function isItContract(address addr) internal view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }
	
	
}


interface iMoonCoin {
    function transfer(address recipient, uint256 amount) external returns (bool);
	function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
	function balanceOf(address account) external view returns (uint256);
}




library SafeMath {
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
        return sub(a, b, "SafeMath: subtraction overflow");
    }
    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
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
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }
    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
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
        return div(a, b, "SafeMath: division by zero");
    }
    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
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
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }
    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
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
        return mod(a, b, "SafeMath: modulo by zero");
    }
    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
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
        require(b != 0, errorMessage);
        return a % b;
    }
}

{
  "remappings": [],
  "optimizer": {
    "enabled": false,
    "runs": 200
  },
  "evmVersion": "istanbul",
  "libraries": {},
  "outputSelection": {
    "*": {
      "*": [
        "evm.bytecode",
        "evm.deployedBytecode",
        "abi"
      ]
    }
  }
}