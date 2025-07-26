import { describe, it, expect, beforeEach } from "vitest"

type Principal = string
type Uint = bigint

const u = (n: number | bigint) => BigInt(n)

const ERR = {
  NOT_AUTHORIZED: 100n,
  WORK_NOT_FOUND: 101n,
  INVALID_SPLIT_LENGTH: 102n,
  INVALID_BPS_SUM: 103n,
  NO_BALANCE: 104n,
  STX_TRANSFER_FAILED: 105n,
  RECIPIENT_ALREADY_SET: 106n,
  EMPTY_RECIPIENTS: 107n,
  NO_SPLIT_VERSION: 108n,
  NOT_WORK_OWNER: 109n,
} as const

const BPS_DENOM = u(10_000)
const MAX_RECIPIENTS = 50

type Work = {
  owner: Principal
  meta: string
  splitVersion: Uint
}

type SplitKey = string
const splitKey = (workId: Uint, version: Uint, recipient: Principal) =>
  `${workId}:${version}:${recipient}`

type IndexKey = string
const indexKey = (workId: Uint, version: Uint) => `${workId}:${version}`

type BalanceKey = string
const balanceKey = (workId: Uint, recipient: Principal) => `${workId}:${recipient}`

const asOk = <T>(value: T) => ({ value })
const asErr = (error: bigint) => ({ error })

const mockContract = {
  admin: "" as Principal,
  workIdCounter: u(0),
  stxBalances: new Map<Principal, Uint>(),
  contractBalance: u(0),

  works: new Map<Uint, Work>(),
  splits: new Map<SplitKey, { bps: Uint }>(),
  splitIndex: new Map<IndexKey, { recipients: Principal[] }>(),
  balances: new Map<BalanceKey, Uint>(),

  isAdmin(caller: Principal) {
    return caller === this.admin
  },

  getWork(workId: Uint) {
    return this.works.get(workId)
  },

  getActiveVersion(workId: Uint) {
    const w = this.works.get(workId)
    if (!w) return asErr(ERR.WORK_NOT_FOUND)
    return asOk(w.splitVersion)
  },

  getClaimable(workId: Uint, who: Principal) {
    return this.balances.get(balanceKey(workId, who)) ?? u(0)
  },

  creditWallet(who: Principal, amount: Uint) {
    this.stxBalances.set(who, (this.stxBalances.get(who) ?? u(0)) + amount)
  },

  debitWallet(who: Principal, amount: Uint) {
    const cur = this.stxBalances.get(who) ?? u(0)
    if (cur < amount) return false
    this.stxBalances.set(who, cur - amount)
    return true
  },

  transferAdmin(caller: Principal, newAdmin: Principal) {
    if (!this.isAdmin(caller)) return asErr(ERR.NOT_AUTHORIZED)
    this.admin = newAdmin
    return asOk(true)
  },

  registerWork(caller: Principal, meta: string) {
    this.workIdCounter += u(1)
    const id = this.workIdCounter
    this.works.set(id, { owner: caller, meta, splitVersion: u(0) })
    return asOk(id)
  },

  transferWorkOwnership(caller: Principal, workId: Uint, newOwner: Principal) {
    const w = this.works.get(workId)
    if (!w) return asErr(ERR.WORK_NOT_FOUND)
    if (!(caller === w.owner || this.isAdmin(caller))) return asErr(ERR.NOT_WORK_OWNER)
    this.works.set(workId, { ...w, owner: newOwner })
    return asOk(true)
  },

  // *** OWNER-ONLY now ***
  setSplits(
    caller: Principal,
    workId: Uint,
    recipients: Principal[],
    bpsList: Uint[],
  ) {
    const w = this.works.get(workId)
    if (!w) return asErr(ERR.WORK_NOT_FOUND)
    if (caller !== w.owner) return asErr(ERR.NOT_WORK_OWNER)

    if (recipients.length === 0) return asErr(ERR.EMPTY_RECIPIENTS)
    if (recipients.length !== bpsList.length) return asErr(ERR.INVALID_SPLIT_LENGTH)
    if (recipients.length > MAX_RECIPIENTS) return asErr(ERR.INVALID_SPLIT_LENGTH)

    let total = u(0)
    for (const b of bpsList) total += b
    if (total !== BPS_DENOM) return asErr(ERR.INVALID_BPS_SUM)

    const newVersion = w.splitVersion + u(1)

    for (let i = 0; i < recipients.length; i++) {
      const r = recipients[i]
      const bps = bpsList[i]
      this.splits.set(splitKey(workId, newVersion, r), { bps })
    }
    this.splitIndex.set(indexKey(workId, newVersion), { recipients })

    this.works.set(workId, { ...w, splitVersion: newVersion })

    return asOk(newVersion)
  },

  deposit(caller: Principal, workId: Uint, amount: Uint) {
    const w = this.works.get(workId)
    if (!w) return asErr(ERR.WORK_NOT_FOUND)
    const version = w.splitVersion
    const idx = this.splitIndex.get(indexKey(workId, version))
    if (!idx) return asErr(ERR.NO_SPLIT_VERSION)

    if (!this.debitWallet(caller, amount)) return asErr(ERR.STX_TRANSFER_FAILED)
    this.contractBalance += amount

    for (const r of idx.recipients) {
      const s = this.splits.get(splitKey(workId, version, r))
      if (!s) return asErr(ERR.NO_SPLIT_VERSION)
      const share = (amount * s.bps) / BPS_DENOM
      const key = balanceKey(workId, r)
      const cur = this.balances.get(key) ?? u(0)
      this.balances.set(key, cur + share)
    }

    return asOk(true)
  },

  claim(caller: Principal, workId: Uint) {
    const key = balanceKey(workId, caller)
    const bal = this.balances.get(key) ?? u(0)
    if (bal === u(0)) return asErr(ERR.NO_BALANCE)
    this.balances.set(key, u(0))

    if (this.contractBalance < bal) return asErr(ERR.STX_TRANSFER_FAILED)
    this.contractBalance -= bal
    this.creditWallet(caller, bal)
    return asOk(bal)
  },
}

const A = "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM"
const B = "ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG"
const C = "ST3NBRSFKX28FQ2ZJ1MAKX58HKHSDGNV5N7R21XCP"
const D = "ST21T9A4FZ0G9PQG5X2FM1A8PW5ZK8J49FGP8Z90J"

describe("royalty-splits.clar (mocked, owner-only splits)", () => {
  beforeEach(() => {
    mockContract.admin = A
    mockContract.workIdCounter = u(0)
    mockContract.contractBalance = u(0)

    mockContract.works = new Map()
    mockContract.splits = new Map()
    mockContract.splitIndex = new Map()
    mockContract.balances = new Map()

    mockContract.stxBalances = new Map()
    mockContract.creditWallet(A, u(1_000_000_000))
    mockContract.creditWallet(B, u(1_000_000_000))
    mockContract.creditWallet(C, u(1_000_000_000))
    mockContract.creditWallet(D, u(1_000_000_000))
  })

  it("registers a work and sets splits (owner)", () => {
    const reg = mockContract.registerWork(A, "song-001")
    const workId = reg.value!

    const setRes = mockContract.setSplits(
      A,
      workId,
      [A, B, C],
      [u(5000), u(3000), u(2000)],
    )
    expect(setRes).toEqual({ value: u(1) })
  })

  it("rejects non-owner setting splits (admin cannot override)", () => {
    const reg = mockContract.registerWork(A, "song-001")
    const workId = reg.value!

    const res = mockContract.setSplits(
      B,
      workId,
      [A, B],
      [u(5000), u(5000)],
    )
    expect(res).toEqual({ error: ERR.NOT_WORK_OWNER })
  })

  it("rejects invalid bps sum", () => {
    const reg = mockContract.registerWork(A, "song-001")
    const workId = reg.value!

    const res = mockContract.setSplits(
      A,
      workId,
      [A, B],
      [u(6000), u(3000)],
    )
    expect(res).toEqual({ error: ERR.INVALID_BPS_SUM })
  })

  it("distributes deposits to recipients correctly & supports claims", () => {
    const workId = mockContract.registerWork(A, "song-royalty").value!
    mockContract.setSplits(A, workId, [A, B, C], [u(5000), u(3000), u(2000)])

    const depositAmount = u(100_000_000)
    const beforeA = mockContract.stxBalances.get(A)!
    const res = mockContract.deposit(A, workId, depositAmount)
    expect(res).toEqual({ value: true })
    expect(mockContract.stxBalances.get(A)).toBe(beforeA - depositAmount)
    expect(mockContract.contractBalance).toBe(depositAmount)

    expect(mockContract.getClaimable(workId, A)).toBe(u(50_000_000))
    expect(mockContract.getClaimable(workId, B)).toBe(u(30_000_000))
    expect(mockContract.getClaimable(workId, C)).toBe(u(20_000_000))

    const beforeB = mockContract.stxBalances.get(B)!
    const claimB = mockContract.claim(B, workId)
    expect(claimB).toEqual({ value: u(30_000_000) })
    expect(mockContract.stxBalances.get(B)).toBe(beforeB + u(30_000_000))
    expect(mockContract.getClaimable(workId, B)).toBe(u(0))
  })

  it("prevents claiming when no balance", () => {
    const workId = mockContract.registerWork(A, "x").value!
    mockContract.setSplits(A, workId, [A], [u(10000)])
    const res = mockContract.claim(A, workId)
    expect(res).toEqual({ error: ERR.NO_BALANCE })
  })

  it("supports versioned splits (owner-only)", () => {
    const workId = mockContract.registerWork(A, "song").value!
    mockContract.setSplits(A, workId, [A, B], [u(7000), u(3000)])
    mockContract.deposit(A, workId, u(100_000_000))

    const v2 = mockContract.setSplits(A, workId, [A, B], [u(5000), u(5000)])
    expect(v2).toEqual({ value: u(2) })
    mockContract.deposit(A, workId, u(100_000_000))

    expect(mockContract.getClaimable(workId, A)).toBe(u(120_000_000))
    expect(mockContract.getClaimable(workId, B)).toBe(u(80_000_000))
  })

  it("transfers work ownership; old owner (who is also admin) can no longer set splits", () => {
    const workId = mockContract.registerWork(A, "song").value!
    mockContract.setSplits(A, workId, [A], [u(10000)])

    const res = mockContract.transferWorkOwnership(A, workId, B)
    expect(res).toEqual({ value: true })

    // new owner (B) can set splits
    const r2 = mockContract.setSplits(B, workId, [B], [u(10000)])
    expect(r2).toEqual({ value: u(2) })

    // old owner/admin (A) cannot override now
    const r3 = mockContract.setSplits(A, workId, [A], [u(10000)])
    expect(r3).toEqual({ error: ERR.NOT_WORK_OWNER })
  })
})
