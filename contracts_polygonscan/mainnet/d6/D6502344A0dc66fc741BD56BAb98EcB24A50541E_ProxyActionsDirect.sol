pragma solidity 0.7.6;

import "./complifi-amm/IPool.sol";
import "./complifi-amm/libs/complifi/tokens/IERC20Metadata.sol";
import "./complifi-amm/plp/IPermanentLiquidityPool.sol";

/// @title CompliFi direct and composite AMM and issuance methods
contract ProxyActionsDirect {

    uint public constant BONE = 10**18;

    // Using vars to avoid stack do deep error
    struct Vars {
        IERC20 collateralToken;
        IERC20 primaryToken;
        IERC20 complementToken;
        IVault vault;
        IPool pool;
        uint256 primaryTokenBalance;
        uint256 complementTokenBalance;
        uint256 primaryTokenAmount;
        uint256 complementTokenAmount;
        IERC20 derivativeIn;
        IERC20 derivativeOut;
        uint256 tokenDecimals;
    }

    /// @notice Mint derivatives by depositing collateral to vault
    function mint(
        address _vault,
        uint256 _collateralAmount
    ) external {

        Vars memory vars;
        vars.vault = IVault(_vault);
        vars.collateralToken = IERC20(vars.vault.collateralToken());

        // Transfer collateral from user to Proxy
        require(
            vars.collateralToken.transferFrom(msg.sender, address(this), _collateralAmount),
            "COLLATERAL_IN"
        );

        vars.collateralToken.approve(_vault, _collateralAmount);

        vars.vault.mintTo(msg.sender, _collateralAmount);
    }

    /// @notice Redeem a symmetric portfolio of live derivatives for underlying collateral
    function refund(
        address _vault,
        uint256 _tokenAmount
    ) external {

        Vars memory vars;
        vars.vault = IVault(_vault);
        vars.primaryToken = IERC20(vars.vault.primaryToken());
        vars.complementToken = IERC20(vars.vault.complementToken());

        require(
            vars.primaryToken.transferFrom(msg.sender, address(this), _tokenAmount),
            "PRIMARY_IN"
        );

        require(
            vars.complementToken.transferFrom(msg.sender, address(this), _tokenAmount),
            "COLLATERAL_IN"
        );

        vars.primaryToken.approve(_vault, _tokenAmount);
        vars.complementToken.approve(_vault, _tokenAmount);

        vars.vault.refundTo(msg.sender, _tokenAmount);
    }

    /// @notice Redeem settled derivatives for underlying collateral
    function redeem(
        address _vault,
        uint256 _primaryTokenAmount,
        uint256 _complementTokenAmount,
        uint256[] memory _underlyingEndRoundHints
    ) external {

        Vars memory vars;
        vars.vault = IVault(_vault);
        vars.primaryToken = IERC20(vars.vault.primaryToken());
        vars.complementToken = IERC20(vars.vault.complementToken());

        // Transfer collateral from user to Proxy
        if(_primaryTokenAmount > 0) {
            require(
                vars.primaryToken.transferFrom(msg.sender, address(this), _primaryTokenAmount),
                "PRIMARY_IN"
            );
            vars.primaryToken.approve(_vault, _primaryTokenAmount);
        }

        if(_complementTokenAmount > 0) {
            require(
                vars.complementToken.transferFrom(msg.sender, address(this), _complementTokenAmount),
                "COLLATERAL_IN"
            );
            vars.complementToken.approve(_vault, _complementTokenAmount);
        }

        vars.vault.redeemTo(msg.sender, _primaryTokenAmount, _complementTokenAmount, _underlyingEndRoundHints);
    }

    /// @notice Add liquidity to AMM pool in identical proportion to pool contents
    function joinPool(
        address _pool,
        uint256 _poolAmountOut,
        uint256[2] calldata _maxAmountsIn
    ) external {
        Vars memory vars;
        vars.pool = IPool(_pool);

        vars.vault = IVault(vars.pool.derivativeVault());

        vars.primaryToken = IERC20(vars.vault.primaryToken());
        vars.complementToken = IERC20(vars.vault.complementToken());

        require(
            vars.primaryToken.transferFrom(msg.sender, address(this), _maxAmountsIn[0]),
            "TAKE_PRIMARY"
        );

        require(
            vars.complementToken.transferFrom(msg.sender, address(this), _maxAmountsIn[1]),
            "TAKE_COMPLEMENT"
        );

        vars.primaryToken.approve(_pool, _maxAmountsIn[0]);
        vars.complementToken.approve(_pool, _maxAmountsIn[1]);

        vars.pool.joinPool(_poolAmountOut,_maxAmountsIn);

        // Return Remaining tokens
        if (vars.primaryToken.balanceOf(address(this)) > 0) {
            require(
                vars.primaryToken.transfer(msg.sender,vars.primaryToken.balanceOf(address(this))),
                "GIVE_PRIMARY"
            );
        }

        if (vars.complementToken.balanceOf(address(this)) > 0) {
            require(
                    vars.complementToken.transfer(msg.sender,vars.complementToken.balanceOf(address(this))),
                    "GIVE_COMPLEMENT"
                );
        }

        // Transfer Pool Tokens To users
        require (vars.pool.transfer( msg.sender, vars.pool.balanceOf(address(this))), "GIVE_POOL");
    }

    /// @notice Swap between derivatives contained in a single AMM pool
    function swap(
        address _pool,
        address _tokenIn,
        uint256 _tokenAmountIn,
        address _tokenOut,
        uint256 _minAmountOut
    ) external {

        swapInternal(_pool, _tokenIn, _tokenAmountIn, _tokenOut, _minAmountOut);
    }

    function swapInternal(
        address _pool,
        address _tokenIn,
        uint256 _tokenAmountIn,
        address _tokenOut,
        uint256 _minAmountOut
    ) internal {

        Vars memory vars;
        vars.pool = IPool(_pool);

        IERC20 tokenIn = IERC20(_tokenIn);
        IERC20 tokenOut = IERC20(_tokenOut);

        // Transfer tokens from user to Proxy
        require(
            tokenIn.transferFrom(msg.sender, address(this), _tokenAmountIn),
            "TAKE_IN"
        );

        tokenIn.approve(_pool, _tokenAmountIn);

        vars.pool.swapExactAmountIn(_tokenIn,_tokenAmountIn,_tokenOut,_minAmountOut);

        require(
            tokenOut.transfer(msg.sender, tokenOut.balanceOf(address(this))),
            "GIVE_OUT"
        );
    }

    function swapPermanent(
        address _plPool,
        uint256[] memory _underlyingEndRoundHints,
        address _pool,
        address _tokenIn,
        uint256 _tokenAmountIn,
        address _tokenOut,
        uint256 _minAmountOut
    ) external {
        IPermanentLiquidityPool(_plPool).rollOver(_underlyingEndRoundHints);

        swapInternal(_pool, _tokenIn, _tokenAmountIn, _tokenOut, _minAmountOut);
    }

    /// @notice Remove liquidity from AMM pool
    function exitPool(
        address _pool,
        uint256 _poolAmountIn,
        uint256[2] calldata _minAmountsOut
    ) external {
        Vars memory vars;
        vars.pool = IPool(_pool);

        vars.vault = IVault(vars.pool.derivativeVault());

        vars.primaryToken = IERC20(vars.vault.primaryToken());
        vars.complementToken = IERC20(vars.vault.complementToken());
        vars.collateralToken = IERC20(vars.vault.collateralToken());

        require(
            vars.pool.transferFrom(msg.sender, address(this), _poolAmountIn),
            "TAKE_POOL"
        );

        vars.pool.exitPool(_poolAmountIn, _minAmountsOut);

        // Transfer Tokens to User Wallet
        require(
            vars.primaryToken.transfer(msg.sender, vars.primaryToken.balanceOf(address(this))),
            "GIVE_PRIMARY"
        );
        require(
            vars.complementToken.transfer(msg.sender, vars.complementToken.balanceOf(address(this))),
            "GIVE_COMPLEMENT"
        );
    }
}

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.7.6;

import './Token.sol';
import './libs/complifi/IVault.sol';

interface IPool is IERC20 {
    function repricingBlock() external view returns (uint256);

    function controller() external view returns (address);

    function baseFee() external view returns (uint256);

    function feeAmpPrimary() external view returns (uint256);

    function feeAmpComplement() external view returns (uint256);

    function maxFee() external view returns (uint256);

    function pMin() external view returns (uint256);

    function qMin() external view returns (uint256);

    function exposureLimitPrimary() external view returns (uint256);

    function exposureLimitComplement() external view returns (uint256);

    function repricerParam1() external view returns (uint256);

    function repricerParam2() external view returns (uint256);

    function derivativeVault() external view returns (IVault);

    function dynamicFee() external view returns (address);

    function repricer() external view returns (address);

    function isFinalized() external view returns (bool);

    function getNumTokens() external view returns (uint256);

    function getTokens() external view returns (address[2] memory tokens);

    function getLeverage(address token) external view returns (uint256);

    function getBalance(address token) external view returns (uint256);

    function joinPool(uint256 poolAmountOut, uint256[2] calldata maxAmountsIn) external;

    function exitPool(uint256 poolAmountIn, uint256[2] calldata minAmountsOut) external;

    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut
    ) external returns (uint256 tokenAmountOut, uint256 spotPriceAfter);

    function paused() external view returns (bool);

    function swappable() external view returns (bool);
    function setSwappable() external;

    function BONE() external pure returns (uint256);
}

// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

interface IERC20Metadata {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

pragma solidity 0.7.6;

import "../Token.sol";

interface IPermanentLiquidityPool is IERC20 {
    function derivativeSpecification() external view returns (address);
    function designatedPoolRegistry() external view returns (address);

    function designatedPool() external view returns (address);

    function rollOver(
        uint256[] calldata _underlyingEndRoundHints
    )
    external;

    function delegate(uint256 tokenAmount)
    external;

    function delegateTo(address recipient, uint256 tokenAmount)
    external;

    function unDelegate(uint256 tokenAmount)
    external;

    function unDelegateTo(address recipient, uint256 tokenAmount)
    external;
}

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.7.6;

import './Num.sol';

// Highly opinionated token implementation

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address whom) external view returns (uint256);

    function allowance(address src, address dst) external view returns (uint256);

    function approve(address dst, uint256 amt) external returns (bool);

    function transfer(address dst, uint256 amt) external returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint256 amt
    ) external returns (bool);
}

contract TokenBase is Num {
    mapping(address => uint256) internal _balance;
    mapping(address => mapping(address => uint256)) internal _allowance;
    uint256 internal _totalSupply;

    event Approval(address indexed src, address indexed dst, uint256 amt);
    event Transfer(address indexed src, address indexed dst, uint256 amt);

    function _mint(uint256 amt) internal {
        _balance[address(this)] = add(_balance[address(this)], amt);
        _totalSupply = add(_totalSupply, amt);
        emit Transfer(address(0), address(this), amt);
    }

    function _burn(uint256 amt) internal {
        require(_balance[address(this)] >= amt, 'INSUFFICIENT_BAL');
        _balance[address(this)] = sub(_balance[address(this)], amt);
        _totalSupply = sub(_totalSupply, amt);
        emit Transfer(address(this), address(0), amt);
    }

    function _move(
        address src,
        address dst,
        uint256 amt
    ) internal {
        require(_balance[src] >= amt, 'INSUFFICIENT_BAL');
        _balance[src] = sub(_balance[src], amt);
        _balance[dst] = add(_balance[dst], amt);
        emit Transfer(src, dst, amt);
    }

    function _push(address to, uint256 amt) internal {
        _move(address(this), to, amt);
    }

    function _pull(address from, uint256 amt) internal {
        _move(from, address(this), amt);
    }
}

contract Token is TokenBase, IERC20 {
    string private _name;
    string private _symbol;
    uint8 private constant _decimals = 18;

    function setName(string memory name) internal {
        _name = name;
    }

    function setSymbol(string memory symbol) internal {
        _symbol = symbol;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function allowance(address src, address dst) external view override returns (uint256) {
        return _allowance[src][dst];
    }

    function balanceOf(address whom) external view override returns (uint256) {
        return _balance[whom];
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function approve(address dst, uint256 amt) external override returns (bool) {
        _allowance[msg.sender][dst] = amt;
        emit Approval(msg.sender, dst, amt);
        return true;
    }

    function increaseApproval(address dst, uint256 amt) external returns (bool) {
        _allowance[msg.sender][dst] = add(_allowance[msg.sender][dst], amt);
        emit Approval(msg.sender, dst, _allowance[msg.sender][dst]);
        return true;
    }

    function decreaseApproval(address dst, uint256 amt) external returns (bool) {
        uint256 oldValue = _allowance[msg.sender][dst];
        if (amt > oldValue) {
            _allowance[msg.sender][dst] = 0;
        } else {
            _allowance[msg.sender][dst] = sub(oldValue, amt);
        }
        emit Approval(msg.sender, dst, _allowance[msg.sender][dst]);
        return true;
    }

    function transfer(address dst, uint256 amt) external override returns (bool) {
        _move(msg.sender, dst, amt);
        return true;
    }

    function transferFrom(
        address src,
        address dst,
        uint256 amt
    ) external override returns (bool) {
        uint256 oldValue = _allowance[src][msg.sender];
        require(msg.sender == src || amt <= oldValue, 'TOKEN_BAD_CALLER');
        _move(src, dst, amt);
        if (msg.sender != src && oldValue != uint256(-1)) {
            _allowance[src][msg.sender] = sub(oldValue, amt);
            emit Approval(msg.sender, dst, _allowance[src][msg.sender]);
        }
        return true;
    }
}

// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "./IDerivativeSpecification.sol";

/// @title Derivative implementation Vault
/// @notice A smart contract that references derivative specification and enables users to mint and redeem the derivative
interface IVault {
    enum State { Created, Live, Settled }

    /// @notice start of live period
    function liveTime() external view returns (uint256);

    /// @notice end of live period
    function settleTime() external view returns (uint256);

    /// @notice redeem function can only be called after the end of the Live period + delay
    function settlementDelay() external view returns (uint256);

    /// @notice underlying value at the start of live period
    function underlyingStarts(uint256 index) external view returns (int256);

    /// @notice underlying value at the end of live period
    function underlyingEnds(uint256 index) external view returns (int256);

    /// @notice primary token conversion rate multiplied by 10 ^ 12
    function primaryConversion() external view returns (uint256);

    /// @notice complement token conversion rate multiplied by 10 ^ 12
    function complementConversion() external view returns (uint256);

    /// @notice protocol fee multiplied by 10 ^ 12
    function protocolFee() external view returns (uint256);

    /// @notice limit on author fee multiplied by 10 ^ 12
    function authorFeeLimit() external view returns (uint256);

    // @notice protocol's fee receiving wallet
    function feeWallet() external view returns (address);

    // @notice current state of the vault
    function state() external view returns (State);

    // @notice derivative specification address
    function derivativeSpecification()
        external
        view
        returns (IDerivativeSpecification);

    // @notice collateral token address
    function collateralToken() external view returns (address);

    // @notice oracle address
    function oracles(uint256 index) external view returns (address);

    function oracleIterators(uint256 index) external view returns (address);

    // @notice collateral split address
    function collateralSplit() external view returns (address);

    // @notice derivative's token builder strategy address
    function tokenBuilder() external view returns (address);

    function feeLogger() external view returns (address);

    // @notice primary token address
    function primaryToken() external view returns (address);

    // @notice complement token address
    function complementToken() external view returns (address);

    /// @notice Switch to Settled state if appropriate time threshold is passed and
    /// set underlyingStarts value and set underlyingEnds value,
    /// calculate primaryConversion and complementConversion params
    /// @dev Reverts if underlyingStart or underlyingEnd are not available
    /// Vault cannot settle when it paused
    function settle(uint256[] calldata _underlyingEndRoundHints) external;

    function mintTo(address _recipient, uint256 _collateralAmount) external;

    /// @notice Mints primary and complement derivative tokens
    /// @dev Checks and switches to the right state and does nothing if vault is not in Live state
    function mint(uint256 _collateralAmount) external;

    /// @notice Refund equal amounts of derivative tokens for collateral at any time
    function refund(uint256 _tokenAmount) external;

    function refundTo(address _recipient, uint256 _tokenAmount) external;

    function redeemTo(
        address _recipient,
        uint256 _primaryTokenAmount,
        uint256 _complementTokenAmount,
        uint256[] calldata _underlyingEndRoundHints
    ) external;

    /// @notice Redeems unequal amounts previously calculated conversions if the vault is in Settled state
    function redeem(
        uint256 _primaryTokenAmount,
        uint256 _complementTokenAmount,
        uint256[] calldata _underlyingEndRoundHints
    ) external;
}

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.7.6;

import './Const.sol';

contract Num is Const {

    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a + b;
        require(c >= a, 'ADD_OVERFLOW');
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        bool flag;
        (c, flag) = subSign(a, b);
        require(!flag, 'SUB_UNDERFLOW');
    }

    function subSign(uint256 a, uint256 b) internal pure returns (uint256, bool) {
        if (a >= b) {
            return (a - b, false);
        } else {
            return (b - a, true);
        }
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        uint256 c0 = a * b;
        require(a == 0 || c0 / a == b, 'MUL_OVERFLOW');
        uint256 c1 = c0 + (BONE / 2);
        require(c1 >= c0, 'MUL_OVERFLOW');
        c = c1 / BONE;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b != 0, 'DIV_ZERO');
        uint256 c0 = a * BONE;
        require(a == 0 || c0 / a == BONE, 'DIV_INTERNAL'); // mul overflow
        uint256 c1 = c0 + (b / 2);
        require(c1 >= c0, 'DIV_INTERNAL'); //  add require
        c = c1 / b;
    }

    function min(uint256 first, uint256 second) internal pure returns (uint256) {
        if (first < second) {
            return first;
        }
        return second;
    }
}

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.7.6;

contract Const {
    uint8 public constant BONE_DECIMALS = 20;
    uint256 public constant BONE = 10**BONE_DECIMALS;
    int256 public constant iBONE = int256(BONE);
}

// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

/// @title Derivative Specification interface
/// @notice Immutable collection of derivative attributes
/// @dev Created by the derivative's author and published to the DerivativeSpecificationRegistry
interface IDerivativeSpecification {
    /// @notice Proof of a derivative specification
    /// @dev Verifies that contract is a derivative specification
    /// @return true if contract is a derivative specification
    function isDerivativeSpecification() external pure returns (bool);

    /// @notice Set of oracles that are relied upon to measure changes in the state of the world
    /// between the start and the end of the Live period
    /// @dev Should be resolved through OracleRegistry contract
    /// @return oracle symbols
    function oracleSymbols() external view returns (bytes32[] memory);

    /// @notice Algorithm that, for the type of oracle used by the derivative,
    /// finds the value closest to a given timestamp
    /// @dev Should be resolved through OracleIteratorRegistry contract
    /// @return oracle iterator symbols
    function oracleIteratorSymbols() external view returns (bytes32[] memory);

    /// @notice Type of collateral that users submit to mint the derivative
    /// @dev Should be resolved through CollateralTokenRegistry contract
    /// @return collateral token symbol
    function collateralTokenSymbol() external view returns (bytes32);

    /// @notice Mapping from the change in the underlying variable (as defined by the oracle)
    /// and the initial collateral split to the final collateral split
    /// @dev Should be resolved through CollateralSplitRegistry contract
    /// @return collateral split symbol
    function collateralSplitSymbol() external view returns (bytes32);

    /// @notice Lifecycle parameter that define the length of the derivative's Live period.
    /// @dev Set in seconds
    /// @return live period value
    function livePeriod() external view returns (uint256);

    /// @notice Parameter that determines starting nominal value of primary asset
    /// @dev Units of collateral theoretically swappable for 1 unit of primary asset
    /// @return primary nominal value
    function primaryNominalValue() external view returns (uint256);

    /// @notice Parameter that determines starting nominal value of complement asset
    /// @dev Units of collateral theoretically swappable for 1 unit of complement asset
    /// @return complement nominal value
    function complementNominalValue() external view returns (uint256);

    /// @notice Minting fee rate due to the author of the derivative specification.
    /// @dev Percentage fee multiplied by 10 ^ 12
    /// @return author fee
    function authorFee() external view returns (uint256);

    /// @notice Symbol of the derivative
    /// @dev Should be resolved through DerivativeSpecificationRegistry contract
    /// @return derivative specification symbol
    function symbol() external view returns (string memory);

    /// @notice Return optional long name of the derivative
    /// @dev Isn't used directly in the protocol
    /// @return long name
    function name() external view returns (string memory);

    /// @notice Optional URI to the derivative specs
    /// @dev Isn't used directly in the protocol
    /// @return URI to the derivative specs
    function baseURI() external view returns (string memory);

    /// @notice Derivative spec author
    /// @dev Used to set and receive author's fee
    /// @return address of the author
    function author() external view returns (address);
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