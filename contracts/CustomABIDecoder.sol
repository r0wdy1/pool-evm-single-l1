//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

contract CustomABIDecoder {
    uint256 constant transfer_nullifier_pos = 4;
    uint256 constant transfer_nullifier_size = 32;
    uint256 constant uint256_size = 32;

    function _loaduint256(uint256 pos) pure internal returns(uint256 r) {
        assembly {
            r := calldataload(pos)
        }
    }

    function _transfer_nullifier() pure internal returns(uint256 r) {
        r = _loaduint256(transfer_nullifier_pos);
    }

    uint256 constant transfer_out_commit_pos = transfer_nullifier_pos + transfer_nullifier_size;
    uint256 constant transfer_out_commit_size = 32;

    function _transfer_out_commit() pure internal returns(uint256 r) {
        r = _loaduint256(transfer_out_commit_pos);
    }

    uint256 constant transfer_index_pos = transfer_out_commit_pos + transfer_out_commit_size;
    uint256 constant transfer_index_size = 6;

    function _transfer_index() pure internal returns(uint48 r) {
        r = uint48(_loaduint256(transfer_index_pos+transfer_index_size-uint256_size));
    }

    uint256 constant transfer_energy_amount_pos = transfer_index_pos + transfer_index_size;
    uint256 constant transfer_energy_amount_size = 14;

    function _transfer_energy_amount() pure internal returns(int112 r) {
        r = int112(uint112(_loaduint256(transfer_energy_amount_pos+transfer_energy_amount_size-uint256_size)));
    }

    uint256 constant transfer_token_amount_pos = transfer_energy_amount_pos + transfer_energy_amount_size;
    uint256 constant transfer_token_amount_size = 8;

    function _transfer_token_amount() pure internal returns(int64 r) {
        r = int64(uint64(_loaduint256(transfer_token_amount_pos+transfer_token_amount_size-uint256_size)));
    }

    uint256 constant transfer_proof_pos = transfer_token_amount_pos + transfer_token_amount_size;
    uint256 constant transfer_proof_size = 256;

    function _transfer_proof() pure internal returns (uint256[8] calldata r) {
        uint256 pos = transfer_proof_pos;
        assembly {
            r := pos
        }
    }

    uint256 constant tree_root_after_pos = transfer_proof_pos + transfer_proof_size;
    uint256 constant tree_root_after_size = 32;

    function _tree_root_after() pure internal returns(uint256 r) {
        r = _loaduint256(tree_root_after_pos);
    }

    uint256 constant tree_proof_pos = tree_root_after_pos + tree_root_after_size;
    uint256 constant tree_proof_size = 256;

    function _tree_proof() pure internal returns (uint256[8] calldata r) {
        uint256 pos = tree_proof_pos;
        assembly {
            r := pos
        }
    }

    uint256 constant tx_type_pos = tree_proof_pos + tree_proof_size;
    uint256 constant tx_type_size = 2;
    uint256 constant tx_type_mask = (1 << (tx_type_size*8)) - 1;

    function _tx_type() pure internal returns(uint256 r) {
        r = _loaduint256(tx_type_pos+tx_type_size-uint256_size) & tx_type_mask;
    }
    
    uint256 constant memo_data_size_pos = tx_type_pos + tx_type_size;
    uint256 constant memo_data_size_size = 2;
    uint256 constant memo_data_size_mask = (1 << (memo_data_size_size*8)) - 1;


    uint256 constant memo_data_pos = memo_data_size_pos + memo_data_size_size;
    function _memo_data_size() pure internal returns(uint256 r) {
        r = _loaduint256(memo_data_size_pos+memo_data_size_size-uint256_size) & memo_data_size_mask;
    }

    function _memo_data() pure internal returns(bytes calldata r) {
        uint256 offset = memo_data_pos;
        uint256 length = _memo_data_size();
        assembly {
            r.offset := offset
            r.length := length
        }
    }

    function _sign_r_vs_pos() pure internal returns(uint256) {
        return memo_data_pos + _memo_data_size();
    }
    
    uint256 constant sign_r_vs_size = 64;

    function _sign_r_vs() pure internal returns(bytes32 r, bytes32 vs) {
        uint256 offset = _sign_r_vs_pos();
        assembly {
            r := calldataload(offset)
            vs := calldataload(add(offset, 32))
        }
    }

    uint256 constant transfer_delta_size = transfer_index_size+transfer_energy_amount_size+transfer_token_amount_size;
    uint256 constant transfer_delta_mask = (1<<(transfer_delta_size*8))-1;

    function _transfer_delta() pure internal returns(uint256 r) {
        r = _loaduint256(transfer_index_pos+transfer_delta_size-uint256_size) & transfer_delta_mask;
    }

    function _memo_fixed_size() pure internal returns(uint256 r) {
        uint256 t = _tx_type();
        if ( t == 0 || t == 1) {
            // fee
            // 8
            r = 8;
        } else if (t == 2) {
            // fee + recipient + native amount
            // 8 + 20 + 8
            r = 36;
        } else if (t == 3) {
            // fee + deadline + address
            // 8 + 8 + 20
            r = 36;
        } else revert(); 
    }

    function _memo_message() pure internal returns(bytes calldata r) {
        uint256 memo_fixed_size = _memo_fixed_size();
        uint256 offset = memo_data_pos+memo_fixed_size;
        uint256 length = _memo_data_size()-memo_fixed_size;
        assembly {
            r.offset := offset
            r.length := length
        }
    }

    uint256 constant memo_fee_pos = memo_data_pos;
    uint256 constant memo_fee_size = 8;
    uint256 constant memo_fee_mask = (1<<(memo_fee_size*8))-1;

    function _memo_fee() pure internal returns(uint256 r) {
        r = _loaduint256(memo_fee_pos+memo_fee_size-uint256_size) & memo_fee_mask;
    }

    // Withdraw specific data

    uint256 constant memo_native_amount_pos = memo_fee_pos + memo_fee_size;
    uint256 constant memo_native_amount_size = 8;
    uint256 constant memo_native_amount_mask = (1<<(memo_native_amount_size*8))-1;

    function _memo_native_amount() pure internal returns(uint256 r) {
        r = _loaduint256(memo_native_amount_pos+memo_native_amount_size-uint256_size) & memo_native_amount_mask;
    }

    uint256 constant memo_receiver_pos = memo_native_amount_pos + memo_native_amount_size;
    uint256 constant memo_receiver_size = 20;

    function _memo_receiver() pure internal returns(address r) {
        r = address(uint160(_loaduint256(memo_receiver_pos+memo_receiver_size-uint256_size)));
    }

    // Peermittable token deposit specific data

    uint256 constant memo_permit_deadline_pos = memo_fee_pos + memo_fee_size;
    uint256 constant memo_permit_deadline_size = 8;

    function _memo_permit_deadline() pure internal returns(uint64 r) {
        r = uint64(_loaduint256(memo_permit_deadline_pos+memo_permit_deadline_size-uint256_size));
    }

    uint256 constant memo_permit_holder_pos = memo_permit_deadline_pos + memo_permit_deadline_size;
    uint256 constant memo_permit_holder_size = 20;

    function _memo_permit_holder() pure internal returns(address r) {
        r = address(uint160(_loaduint256(memo_permit_holder_pos+memo_permit_holder_size-uint256_size)));
    }
}