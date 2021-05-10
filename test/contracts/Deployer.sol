// SPDX-License-Identifier: MIT

pragma solidity >=0.7.5;
pragma abicoder v2;

contract Deployer {
  event Deployed (address payable createdContract, bytes initCode, bytes32 salt);

  function deployContract(bytes memory initCode, bytes32 salt)
    external
    returns (address payable createdContract)
  {
    assembly {
      createdContract := create2(0, add(initCode, 0x20), mload(initCode), salt)
    }
    require(createdContract != address(0), "Deployer: deployContract failed");
    emit Deployed(createdContract, initCode, salt);
  }
}
