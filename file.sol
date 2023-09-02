// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./SafeMath.sol";

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

contract BasicLendingPlatform {
    using SafeMath for uint256;

    struct User {
        mapping(address => uint256) balances;
        mapping(address => uint256) debts;
        uint256 lastUpdated;
    }

    mapping(address => User) public users;
    mapping(address => uint256) public totalLiquidity;
    mapping(address => uint256) public tokenPrices;

    uint256 public annualBorrowInterestRate = 5;
    uint256 public annualDepositInterestRate = 2;
    uint256 public collateralFactor = 50;

    event Deposited(address indexed user, address indexed token, uint256 amount);
    event Borrowed(address indexed user, address indexed token, uint256 amount);
    event Repaid(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);

    // SafeMath library (the same as your previous example)

    function _updateInterest(address _user, address _token) internal {
        User storage user = users[_user];
        uint256 timeElapsed = block.timestamp - user.lastUpdated;

        uint256 balance = user.balances[_token];
        if (balance > 0) {
            uint256 depositInterest = (balance.mul(annualDepositInterestRate).div(31536000)).mul(timeElapsed);
            user.balances[_token] = balance.add(depositInterest);
            totalLiquidity[_token] = totalLiquidity[_token].add(depositInterest);
        }

        uint256 debt = user.debts[_token];
        if (debt > 0) {
            uint256 borrowInterest = (debt.mul(annualBorrowInterestRate).div(31536000)).mul(timeElapsed);
            user.debts[_token] = debt.add(borrowInterest);
        }

        user.lastUpdated = block.timestamp;
    }

    function setTokenPrice(address token, uint256 price) public {
        // Add authorization checks if needed
        tokenPrices[token] = price;
    }

    function deposit(address token, uint256 amount) public {
        uint256 allowance = IERC20(token).allowance(msg.sender, address(this));
        require(allowance >= amount, "Contract not approved for the required amount");
        
        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed");

        _updateInterest(msg.sender, token);
        users[msg.sender].balances[token] = users[msg.sender].balances[token].add(amount);
        totalLiquidity[token] = totalLiquidity[token].add(amount);
        emit Deposited(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount) public {
        _updateInterest(msg.sender, token);

        uint256 available = users[msg.sender].balances[token].sub(users[msg.sender].debts[token]);
        require(amount <= available, "Insufficient available balance");

        bool success = IERC20(token).transfer(msg.sender, amount);
        require(success, "Transfer failed");

        users[msg.sender].balances[token] = users[msg.sender].balances[token].sub(amount);
        totalLiquidity[token] = totalLiquidity[token].sub(amount);
        emit Withdrawn(msg.sender, token, amount);
    }

    function borrow(address depositToken, address borrowToken, uint256 borrowAmount) public {
        _updateInterest(msg.sender, borrowToken);

        require(totalLiquidity[borrowToken] >= borrowAmount, "Insufficient liquidity");

        uint256 depositAmountInBase = users[msg.sender].balances[depositToken].mul(tokenPrices[depositToken]);
        uint256 borrowAmountInBase = borrowAmount.mul(tokenPrices[borrowToken]);

        uint256 maxBorrowInBase = (depositAmountInBase.mul(collateralFactor)).div(100);
        require(users[msg.sender].debts[borrowToken].add(borrowAmountInBase) <= maxBorrowInBase, "Exceeds collateral limit");

        bool success = IERC20(borrowToken).transfer(msg.sender, borrowAmount);
        require(success, "Transfer failed");

        users[msg.sender].debts[borrowToken] = users[msg.sender].debts[borrowToken].add(borrowAmountInBase);
        totalLiquidity[borrowToken] = totalLiquidity[borrowToken].sub(borrowAmount);
        emit Borrowed(msg.sender, borrowToken, borrowAmount);
    }

    function repay(address token, uint256 amount) public {
        uint256 allowance = IERC20(token).allowance(msg.sender, address(this));
        require(allowance >= amount, "Contract not approved for the required amount");

        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed");

        _updateInterest(msg.sender, token);
        users[msg.sender].debts[token] = users[msg.sender].debts[token].sub(amount);
        totalLiquidity[token] = totalLiquidity[token].add(amount);
        emit Repaid(msg.sender, token, amount);
    }
}