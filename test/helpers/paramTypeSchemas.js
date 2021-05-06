module.exports = {
  EXECUTE_CALL_PARAM_TYPES: [
    { name: 'value', type: 'uint256' },
    { name: 'to', type: 'address' },
    { name: 'data', type: 'bytes' }
  ],
  
  EXECUTE_CALL_WITHOUT_VALUE_PARAM_TYPES: [
    { name: 'to', type: 'address' },
    { name: 'data', type: 'bytes' }
  ],
  
  EXECUTE_CALL_WITHOUT_DATA_PARAM_TYPES: [
    { name: 'value', type: 'uint256' },
    { name: 'to', type: 'address' }
  ],
  
  EXECUTE_DELEGATE_CALL_PARAM_TYPES: [
    { name: 'to', type: 'address' },
    { name: 'data', type: 'bytes' }
  ],
  
  EXECUTE_PARTIAL_SIGNED_DELEGATE_CALL_PARAM_TYPES: [
    { name: 'to', type: 'address' },
    { name: 'data', type: 'bytes' }
  ],

  TOKEN_TO_TOKEN_SWAP_PARAM_TYPES: [
    { name: 'tokenIn', type: 'address' },
    { name: 'tokenOut', type: 'address' },
    { name: 'tokenInAmount', type: 'uint256' },
    { name: 'tokenOutAmount', type: 'uint256' },
    { name: 'expiryBlock', type: 'uint256' }
  ],
  
  ETH_TO_TOKEN_SWAP_PARAM_TYPES: [
    { name: 'token', type: 'address' },
    { name: 'ethAmount', type: 'uint256' },
    { name: 'tokenAmount', type: 'uint256' },
    { name: 'expiryBlock', type: 'uint256' }
  ],
  
  TOKEN_TO_ETH_SWAP_PARAM_TYPES: [
    { name: 'token', type: 'address' },
    { name: 'tokenAmount', type: 'uint256' },
    { name: 'ethAmount', type: 'uint256' },
    { name: 'expiryBlock', type: 'uint256' }
  ],

  CANCEL_PARAM_TYPES: [],

  RECOVERY_CANCEL_PARAM_TYPES: [],

  DELEGATED_SWAP_TOKEN_TO_TOKEN_PARAM_TYPES: [
    { name: 'tokenIn', type: 'address' },
    { name: 'tokenOut', type: 'address' },
    { name: 'tokenInAmount', type: 'uint256' },
    { name: 'tokenOutAmount', type: 'uint256' },
    { name: 'expiryBlock', type: 'uint256' },
    { name: 'to', type: 'address' },
    { name: 'data', type: 'bytes' },
  ]
}
