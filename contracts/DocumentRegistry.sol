// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.37;

/// @notice Registro didatico por conta e SHA-256; nao certifica identidade ou autoria.
contract DocumentRegistry {
    mapping(address => mapping(bytes32 => uint256)) private registeredBlocks;

    error AlreadyRegistered(address account, bytes32 documentHash);
    event DocumentRegistered(address indexed account, bytes32 indexed documentHash, uint256 blockNumber);

    function register(bytes32 documentHash) external {
        if (registeredBlocks[msg.sender][documentHash] != 0) {
            revert AlreadyRegistered(msg.sender, documentHash);
        }
        registeredBlocks[msg.sender][documentHash] = block.number;
        emit DocumentRegistered(msg.sender, documentHash, block.number);
    }

    function lookup(address account, bytes32 documentHash) external view returns (bool exists, uint256 blockNumber) {
        blockNumber = registeredBlocks[account][documentHash];
        exists = blockNumber != 0;
    }
}
