enum Errors {
    NotJudgeSystem = 100
    NotConsumer = 101
    NotProducer = 102
    Unauthorized = 103
    DealAlreadyExists = 110
    DealNotFound = 111
    InvalidAmount = 120
    InvalidFee = 121
    InvalidResponsibility = 122
    ProducerAlreadyPaid = 130
    ProducerDidNotPay = 131
    DealNotExpired = 140
    FreezeTimeNotPassed = 141
    NothingToWithdraw = 150
    InvalidFeePart = 151
    InvalidMessage = 0xFFFF
}

struct Deal {
    id: uint128
    consumer: address
    producer: address
    amount: coins
    producerResponsibility: coins
    expirationTime: uint64
    producerPaid: bool
}

struct Storage {
    id: uint32
    judgeSystem: address
    minimalDealAmount: coins
    feePart: uint8
    feeFund: coins
    systemFailureFreezeTime: uint64
    minimalContractBalance: coins
    minimalAdditionAmountForFee: coins
    totalClientMoney: coins
    deals: map<uint128, Deal>
}

fun Storage.load(): Storage {
    return Storage.fromCell(contract.getData());
}

fun Storage.save(self) {
    contract.setData(self.toCell());
}

struct (0xb6a0e5cf) MakeDeal {
    id: uint128
    producer: address
    producerResponsibility: coins
    expirationTime: uint64
    amount: coins
    fee: coins
}

struct (0x7ca93424) JudgeDeal {
    id: uint128
    isProducerFault: bool
}

struct (0xb3d8dc18) PayResponsibility {
    id: uint128
}

struct (0x4381dd4b) ProducerGiveUpDeal {
    id: uint128
}

struct (0x41dc9946) ConsumerReturnMoneyDueToNotLockedResponsibility {
    id: uint128
}

struct (0x95ef4403) CompleteTheDeal {
    id: uint128
}

struct (0x6f5ee0a5) SystemFailureWithdraw {
    id: uint128
}

struct (0x3df17168) ChangeMinimalDealAmount {
    minimalDealAmount: coins
}

struct (0x6bed33d8) ChangeFeePart {
    feePart: uint8
}

struct (0xe29fdd0b) ChangeSystemFailureFreezeTime {
    systemFailureFreezeTime: uint64
}

struct (0x365f16c7) ChangeMinimalContractBalance {
    minimalContractBalance: coins
}

struct (0x00000000) WithdrawSafe {
    tail: RemainingBitsAndRefs
}
