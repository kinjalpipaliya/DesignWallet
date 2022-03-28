// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (finance/DesignWallet.sol)

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title DesignWallet
 * @dev This contract allows to split Ether payments among a group of accounts. The sender does not need to be aware
 * that the Ether will be split in this way, since it is handled transparently by the contract.
 *
 * The split can be in equal parts or in any other arbitrary proportion. The way this is specified is by assigning each
 * account to a number of shares. Of all the Ether that this contract receives, each account will then be able to claim
 * an amount proportional to the percentage of total shares they were assigned.
 *
 * `DesignWallet` follows a _pull payment_ model. This means that payments are not automatically forwarded to the
 * accounts but kept in this contract, and the actual transfer is triggered as a separate step by calling the {release}
 * function.
 *
 * NOTE: This contract assumes that ERC20 tokens will behave similarly to native tokens (Ether). Rebasing tokens, and
 * tokens that apply fees during transfers, are likely to not be supported as expected. If in doubt, we encourage you
 * to run tests before sending real value to this contract.
 */
contract Wallet is Context, Ownable {
    event PayeeAdded(address account, uint256 shares);
    event PaymentReleased(address to, uint256 amount);
    event ERC20PaymentReleased(IERC20 indexed token, address to, uint256 amount);
    event PaymentReceived(address from, uint256 amount);

    string public _investment; //Investment Name
    IERC20 public _tokenAddress; //Investment Token Address

    address public _0xDesignAddress; //0xDesign Address

    uint256 private _totalShares = 0; //Total Tokens
    uint256 private _totalClaimed = 0; //Total Claimed Tokens
    uint256 private _totalFeesClaimed = 0; //Total Fees Claimed Tokens
    uint256 private _totalFeesCollected = 0; //Total Fees Collected Tokens
    uint256 private _totalReleasedPercent = 0; //Total Released Tokens Percentage

    address[] private _payeeAddresses;

    struct _payee {
        uint256 _shares; //Total user assigned Tokens
        uint256 _tokenClaimed; //User Calimed Tokens
        uint8 _feesPercentage; //User Fees
    }

    mapping (address => _payee) private _payees;

    /**
     * @dev Creates an instance of `DesignWallet` where each account in `payees` is assigned the number of shares at
     * the matching position in the `shares` array.
     *
     * All addresses in `payees` must be non-zero. Both arrays must have the same non-zero length, and there must be no
     * duplicates in `payees`.
     */
    constructor(string memory investment) payable {
        _investment = investment;
    //    _tokenAddress = tokenAddress;
    }

    function setInvestmentName(string memory _invetmentName) public {
        _investment = _invetmentName;
    }

    function getInvestmentName() public view returns (string memory) {
        return _investment;
    }

    /**
     * @dev The Ether received will be logged with {PaymentReceived} events. Note that these events are not fully
     * reliable: it's possible for a contract to receive Ether without triggering this function. This only affects the
     * reliability of the events, and not the actual splitting of Ether.
     *
     * To learn more about this see the Solidity documentation for
     * https://solidity.readthedocs.io/en/latest/contracts.html#fallback-function[fallback
     * functions].
     */
    receive() external payable virtual {
        emit PaymentReceived(_msgSender(), msg.value);
    }

    /**
     * @dev Getter for the total shares held by payees.
     */

    function setTotalShares(uint256 totalSharesSet) public {
        _totalShares = totalSharesSet;
    }

    function totalShares() public view returns (uint256) {
        return _totalShares;
    }

    /**
     * @dev Getter for the total amount of `token` already released. `token` should be the address of an IERC20
     * contract.
     */
    function totalClaimed() public view returns (uint256) {
        return _totalClaimed;
    }

    /**
     * @dev Getter for the amount of shares held by an account.
     */
    function shares(address account) public view returns (uint256) {
        return _payees[account]._shares;
    }

    /**
     * @dev Getter for the amount of `token` tokens already released to a payee. `token` should be the address of an
     * IERC20 contract.
     */
    function claimed(address account) public view returns (uint256) {
        return _payees[account]._tokenClaimed;
    }

    /**
     * @dev Getter for the address of the payee number `index`.
     */
    function payee(uint256 index) public view returns (address) {
        return _payeeAddresses[index];
    }

    /**
     * @dev Triggers a transfer to `account` of the amount of `token` tokens they are owed, according to their
     * percentage of the total shares and their previous withdrawals. `token` must be the address of an IERC20
     * contract.
     */
    function release() public {
        require(_payees[msg.sender]._shares > 0, "DesignWallet: account has no shares");

        uint256 payment = _pendingPayment(msg.sender);

        require(payment != 0, "DesignWallet: account is not due payment");

        _payees[msg.sender]._tokenClaimed += payment;
        _totalClaimed += payment;
        
        uint256 feesPayment = _feesCalculator(msg.sender, payment);
        _totalFeesCollected += feesPayment;

        SafeERC20.safeTransfer(_tokenAddress, msg.sender, payment * 10^18);
        emit ERC20PaymentReleased(_tokenAddress, msg.sender, payment);
    }

    /**
     * @dev internal logic for computing the pending payment of an `account` given the token historical balances and
     * already released amounts.
     */
    function _pendingPayment(address account) private view returns (uint256) {
        return (_payees[account]._shares * _totalReleasedPercent * (100 - _payees[account]._feesPercentage)) / (100 * 100) - claimed(account);
    }

    /**
     * @dev internal logic for computing the fees of an `account` given the token historical balances and
     * already released amounts.
     */
    function _feesCalculator(address account, uint256 payment) private view returns (uint256) {
        return payment * _payees[account]._feesPercentage / (100 - _payees[account]._feesPercentage);
    }

    /**
     * @dev Triggers a transfer to 0xDesign of the amount of Fees tokens they are owed, according to their
     * percentage of the total shares and their previous withdrawals made by users. `token` must be the address of
     * an IERC20 contract.
     */
    function releaseFees() public onlyOwner {
        require(_0xDesignAddress != address(0), "DesignWallet: account is the zero address");

        uint256 feesPayment = _feesPayment();

        require(feesPayment != 0, "DesignWallet: Fees are not due payment");

        _totalFeesClaimed += feesPayment;
        _totalClaimed += feesPayment;

        SafeERC20.safeTransfer(_tokenAddress, _0xDesignAddress, feesPayment * 10^18);
        emit ERC20PaymentReleased(_tokenAddress, _0xDesignAddress, feesPayment);
    }

    /**
     * @dev internal logic for computing the fees of an `account` given the token historical balances and
     * already released amounts.
     */
    function _feesPayment() private view returns (uint256) {
        return _totalFeesCollected - _totalFeesClaimed;
    }

    /**
     * @dev Add a new multiple payees to the contract.
     * @param payees The address of the payee to add.
     * @param shares_ The number of shares owned by the payee.
     * @param fees The Fees of the payee to add.
     */
    function _addPayees(address[] memory payees, uint256[] memory shares_, uint8[] memory fees) public onlyOwner {
        require(payees.length == shares_.length, "DesignWallet: payees and shares length mismatch");
        require(payees.length > 0, "DesignWallet: no payees");

        for (uint256 i = 0; i < payees.length; i++) {
            _addPayee(payees[i], shares_[i], fees[i]);
        }
    }

    /**
     * @dev Add a new payee to the contract.
     * @param account The address of the payee to add.
     * @param shares_ The number of shares owned by the payee.
     */
    function _addPayee(address account, uint256 shares_, uint8 fees) public onlyOwner {
        require(account != address(0), "DesignWallet: account is the zero address");
        require(shares_ > 0, "DesignWallet: shares are 0");
        require(_payees[account]._shares == 0, "DesignWallet: account already has shares");

        _payeeAddresses.push(account);
        _payees[account]._shares = shares_;
        _payees[account]._feesPercentage = fees;
        _payees[account]._tokenClaimed = 0;
        _totalShares = _totalShares + shares_;
        emit PayeeAdded(account, shares_);
    }

    function changeTokenAddress(IERC20 newTokenAddress) public onlyOwner {
        _tokenAddress = newTokenAddress;
    }

    function releaseBatch(uint256 percentage) public onlyOwner {
        _totalReleasedPercent += percentage;
    }

    function setFeesWallet(address walletAddress) public onlyOwner {
        _0xDesignAddress = walletAddress;
    }
}