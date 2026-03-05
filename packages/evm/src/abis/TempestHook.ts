export const TempestHookABI = [
  // View functions
  {
    name: "getVolatility",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [
      { name: "currentVol", type: "uint64" },
      { name: "regime", type: "uint8" },
      { name: "ema7d", type: "uint64" },
      { name: "ema30d", type: "uint64" },
    ],
  },
  {
    name: "getCurrentFee",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [{ name: "feeBps", type: "uint24" }],
  },
  {
    name: "getRecommendedRange",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "poolId", type: "bytes32" },
      { name: "currentTick", type: "int24" },
    ],
    outputs: [
      { name: "lowerTick", type: "int24" },
      { name: "upperTick", type: "int24" },
    ],
  },
  {
    name: "getObservationCount",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [{ name: "", type: "uint16" }],
  },
  {
    name: "getVolState",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "currentVol", type: "uint64" },
          { name: "ema30d", type: "uint64" },
          { name: "ema7d", type: "uint64" },
          { name: "lastUpdate", type: "uint32" },
          { name: "regime", type: "uint8" },
          { name: "sampleCount", type: "uint16" },
        ],
      },
    ],
  },
  {
    name: "isPoolInitialized",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "governance",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    name: "keeperReward",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "minUpdateInterval",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint32" }],
  },
  // Write functions
  {
    name: "updateVolatility",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [],
  },
  {
    name: "setFeeConfig",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "poolId", type: "bytes32" },
      {
        name: "config",
        type: "tuple",
        components: [
          { name: "vol0", type: "uint64" },
          { name: "fee0", type: "uint24" },
          { name: "vol1", type: "uint64" },
          { name: "fee1", type: "uint24" },
          { name: "vol2", type: "uint64" },
          { name: "fee2", type: "uint24" },
          { name: "vol3", type: "uint64" },
          { name: "fee3", type: "uint24" },
          { name: "vol4", type: "uint64" },
          { name: "fee4", type: "uint24" },
          { name: "vol5", type: "uint64" },
          { name: "fee5", type: "uint24" },
        ],
      },
    ],
    outputs: [],
  },
  {
    name: "setKeeperReward",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "_reward", type: "uint256" }],
    outputs: [],
  },
  {
    name: "setMinUpdateInterval",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "_interval", type: "uint32" }],
    outputs: [],
  },
  {
    name: "transferGovernance",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "newGovernance", type: "address" }],
    outputs: [],
  },
  // Events
  {
    name: "PoolRegistered",
    type: "event",
    inputs: [
      { name: "poolId", type: "bytes32", indexed: true },
      { name: "initialTick", type: "int24", indexed: false },
    ],
  },
  {
    name: "TickRecorded",
    type: "event",
    inputs: [
      { name: "poolId", type: "bytes32", indexed: true },
      { name: "tick", type: "int24", indexed: false },
      { name: "timestamp", type: "uint32", indexed: false },
    ],
  },
  {
    name: "VolatilityUpdated",
    type: "event",
    inputs: [
      { name: "poolId", type: "bytes32", indexed: true },
      { name: "currentVol", type: "uint64", indexed: false },
      { name: "regime", type: "uint8", indexed: false },
      { name: "newFee", type: "uint24", indexed: false },
      { name: "sampleCount", type: "uint16", indexed: false },
    ],
  },
  {
    name: "FeeConfigUpdated",
    type: "event",
    inputs: [{ name: "poolId", type: "bytes32", indexed: true }],
  },
  {
    name: "GovernanceTransferred",
    type: "event",
    inputs: [
      { name: "oldGov", type: "address", indexed: true },
      { name: "newGov", type: "address", indexed: true },
    ],
  },
] as const;
