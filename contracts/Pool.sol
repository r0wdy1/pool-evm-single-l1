//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ITransferVerifier.sol";
import "./interfaces/ITreeVerifier.sol";
import "./interfaces/IMintable.sol";
import "./Parameters.sol";
import "./manager/interfaces/IOperatorManager.sol";
import "./interfaces/IERC20Receiver.sol";
import "./interfaces/IWXDAI.sol";

contract Pool is Parameters, Initializable, IERC20Receiver, Ownable {
    using SafeERC20 for IWXDAI;

    uint256 immutable public pool_id;
    IMintable immutable public voucher_token;
    uint256 immutable public denominator;
    uint256 immutable public energy_denominator;
    uint256 immutable public native_denominator;
    ITransferVerifier immutable public transfer_verifier;
    ITreeVerifier immutable public tree_verifier;
    IOperatorManager immutable public operatorManager;
    uint256 immutable internal first_root;
    address immutable public bridge_address;
    IWXDAI immutable public wxdai;

    uint256 constant internal MAX_POOL_ID = 0xffffff;



    modifier onlyOperator() {
        require(operatorManager.is_operator(), "You are not an operator at this time");
        _;
    }

    mapping (address => uint256) public bridge_deposits;
    mapping (uint256 => uint256) public nullifiers;
    mapping (uint256 => uint256) public roots;
    uint256 public pool_index;
    bytes32 public all_messages_hash;

    

    constructor(
        uint256 __pool_id,
        IWXDAI _wxdai,
        IMintable _voucher_token,
        uint256 _denominator,
        uint256 _energy_denominator,
        uint256 _native_denominator,
        ITransferVerifier _transfer_verifier,
        ITreeVerifier _tree_verifier,
        IOperatorManager _operatorManager,
        uint256 _first_root,
        address _bridge_address
    ) {
        require(__pool_id <= MAX_POOL_ID);
        wxdai=_wxdai;
        voucher_token=_voucher_token;
        denominator=_denominator;
        energy_denominator=_energy_denominator;
        native_denominator=_native_denominator;
        transfer_verifier=_transfer_verifier;
        tree_verifier=_tree_verifier;
        operatorManager=_operatorManager;
        first_root = _first_root;
        pool_id = __pool_id;
        bridge_address = _bridge_address;
    }

    function initialize() public initializer{
        roots[0] = first_root;
    }

    event Message(uint256 indexed index, bytes32 indexed hash, bytes message);

    function _root_before() internal view override returns(uint256) {
        return roots[pool_index];
    }

    function _root() internal view override returns(uint256) {
        return roots[_transfer_index()];
    }

    function _pool_id() internal view override returns(uint256) {
        return pool_id;
    }

    function transact() external payable onlyOperator {
        {
            uint256 _pool_index = pool_index;

            require(transfer_verifier.verifyProof(_transfer_pub(), _transfer_proof()), "bad transfer proof"); 
            require(nullifiers[_transfer_nullifier()]==0,"doublespend detected");
            require(_transfer_index() <= _pool_index, "transfer index out of bounds");
            require(tree_verifier.verifyProof(_tree_pub(), _tree_proof()), "bad tree proof");

            nullifiers[_transfer_nullifier()] = uint256(keccak256(abi.encodePacked(_transfer_out_commit(), _transfer_delta())));
            _pool_index +=128;
            roots[_pool_index] = _tree_root_after();
            pool_index = _pool_index;
            bytes memory message = _memo_message();
            bytes32 message_hash = keccak256(message);
            bytes32 _all_messages_hash = keccak256(abi.encodePacked(all_messages_hash, message_hash));
            all_messages_hash = _all_messages_hash;
            emit Message(_pool_index, _all_messages_hash, message);
        }


        uint256 fee = _memo_fee();
        int256 token_amount = _transfer_token_amount() + int256(fee);
        int256 energy_amount = _transfer_energy_amount();

        if (_tx_type()==0) { // Deposit
            require(token_amount>=0 && energy_amount==0 && msg.value == 0, "incorrect deposit amounts");
            wxdai.safeTransferFrom(_deposit_spender(), address(this), uint256(token_amount) * denominator);
        } else if (_tx_type()==1) { // Transfer
            require(token_amount==0 && energy_amount==0 && msg.value == 0, "incorrect transfer amounts");
        } else if (_tx_type()==2) { // Withdraw
            require(token_amount<=0 && energy_amount<=0 && msg.value == _memo_native_amount()*native_denominator, "incorrect withdraw amounts");

            if (token_amount<0) {
                wxdai.safeTransfer(_memo_receiver(), uint256(-token_amount)*denominator);
            }

            if (energy_amount<0) {
                require(address(voucher_token)!=address(0), "no voucher token");
                require(voucher_token.mint(_memo_receiver(), uint256(-energy_amount)*energy_denominator));
            }

            if (msg.value > 0) {
                (bool success, ) = payable(_memo_receiver()).call{value:msg.value}("");
                require(success);
            }

        } else if (_tx_type()==3) { // Bridge deposit
            require(token_amount>=0 && energy_amount==0 && msg.value == 0, "incorrect deposit amounts");
            require(bridge_deposits[_deposit_spender()] >= uint256(token_amount) * denominator, "not enough tokens for deposit");
            bridge_deposits[_deposit_spender()] -= uint256(token_amount) * denominator;
        } else revert("Incorrect transaction type");

        if (fee>0) {
            wxdai.safeTransfer(msg.sender, fee*denominator);
        }
    }

    function onTokenBridged(
        address _token,
        uint256 _value,
        bytes calldata _data
    ) external {
        require(address(wxdai) == _token, "token is not supproted");
        wxdai.withdraw(_value);
        address user = address(uint160(bytes20(_data)));
        bridge_deposits[user] += _value;
    }

    function claimBridgeDeposit(uint256 value) external {
        require(bridge_deposits[msg.sender] >= value, "not enough tokens to claim");
        wxdai.safeTransfer(msg.sender, value);
        bridge_deposits[msg.sender] -= value;
    }

    function swapXDAItoWXDAI(uint256 amount) external onlyOwner {
        wxdai.deposit{value: amount}();
    }
}

