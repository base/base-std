// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @title  IERC165
/// @author Ethereum (ERC-165)
///
/// @notice Standard interface-detection interface.
///
/// @dev    Interface ID: `0x01ffc9a7`. Declared locally because base-std carries no external
///         dependency that provides it (ERC-165 is greenfield here).
interface IERC165 {
    /// @notice Whether this contract implements the interface defined by `interfaceId`.
    ///
    /// @param interfaceId The interface identifier, per ERC-165.
    ///
    /// @return `true` if the contract implements `interfaceId` and `interfaceId != 0xffffffff`.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
