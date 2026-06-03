import "types"

contract SolomonDeal {
    author: "Solomon Deal"
    version: "0.1.0"
    description: "Escrow contract compatible with the existing Solomon Deal bot API"
    storage: Storage
    incomingMessages: AllowedMessage
}

type AllowedMessage =
    | MakeDeal
    | JudgeDeal
    | PayResponsibility
    | ProducerGiveUpDeal
    | ConsumerReturnMoneyDueToNotLockedResponsibility
    | CompleteTheDeal
    | SystemFailureWithdraw
    | ChangeMinimalDealAmount
    | ChangeFeePart
    | ChangeSystemFailureFreezeTime
    | ChangeMinimalContractBalance
    | WithdrawSafe

fun onInternalMessage(in: InMessage) {
    val msg = lazy AllowedMessage.fromSlice(in.body);

    match (msg) {
        MakeDeal => handleMakeDeal(in.senderAddress, in.valueCoins, msg),
        PayResponsibility => handlePayResponsibility(in.senderAddress, in.valueCoins, msg),
        CompleteTheDeal => handleCompleteTheDeal(in.senderAddress, msg),
        ProducerGiveUpDeal => handleProducerGiveUpDeal(in.senderAddress, msg),
        ConsumerReturnMoneyDueToNotLockedResponsibility => {
            handleConsumerReturnMoneyDueToNotLockedResponsibility(in.senderAddress, msg);
        }
        JudgeDeal => handleJudgeDeal(in.senderAddress, in.createdAt, msg),
        SystemFailureWithdraw => handleSystemFailureWithdraw(in.senderAddress, in.createdAt, msg),
        ChangeMinimalDealAmount => handleChangeMinimalDealAmount(in.senderAddress, msg),
        ChangeFeePart => handleChangeFeePart(in.senderAddress, msg),
        ChangeSystemFailureFreezeTime => handleChangeSystemFailureFreezeTime(in.senderAddress, msg),
        ChangeMinimalContractBalance => handleChangeMinimalContractBalance(in.senderAddress, msg),
        WithdrawSafe => handleWithdrawSafe(in.senderAddress),
        else => {
            assert (in.body.isEmpty()) throw Errors.InvalidMessage;
        }
    }
}

fun onBouncedMessage(_in: InMessageBounced) {}

fun handleMakeDeal(sender: address, value: coins, msg: MakeDeal) {
    var storage = lazy Storage.load();

    assert (!storage.deals.exists(msg.id)) throw Errors.DealAlreadyExists;
    assert (msg.amount >= storage.minimalDealAmount) throw Errors.InvalidAmount;
    assert (msg.amount > 0) throw Errors.InvalidAmount;
    assert (msg.producerResponsibility >= 0) throw Errors.InvalidResponsibility;
    assert (msg.fee == (msg.amount / storage.feePart)) throw Errors.InvalidFee;
    assert (
        value >= msg.amount + msg.fee + storage.minimalAdditionAmountForFee
    ) throw Errors.InvalidAmount;

    val deal = Deal {
        id: msg.id,
        consumer: sender,
        producer: msg.producer,
        amount: msg.amount,
        producerResponsibility: msg.producerResponsibility,
        expirationTime: msg.expirationTime,
        producerPaid: false,
    };

    storage.deals.set(msg.id, deal);
    storage.feeFund += msg.fee;
    storage.totalClientMoney += msg.amount;
    storage.save();
}

fun handlePayResponsibility(sender: address, value: coins, msg: PayResponsibility) {
    var storage = lazy Storage.load();
    var deal = loadDeal(storage, msg.id);

    assert (sender == deal.producer) throw Errors.NotProducer;
    assert (!deal.producerPaid) throw Errors.ProducerAlreadyPaid;
    assert (value >= deal.producerResponsibility) throw Errors.InvalidResponsibility;

    deal.producerPaid = true;
    storage.totalClientMoney += deal.producerResponsibility;
    storage.deals.set(msg.id, deal);
    storage.save();
}

fun handleCompleteTheDeal(sender: address, msg: CompleteTheDeal) {
    var storage = lazy Storage.load();
    val deal = loadDeal(storage, msg.id);

    assert (sender == storage.judgeSystem || sender == deal.consumer) throw Errors.Unauthorized;

    storage.deals.delete(msg.id);
    storage.totalClientMoney -= deal.amount;

    var payout = deal.amount;
    if (deal.producerPaid) {
        storage.totalClientMoney -= deal.producerResponsibility;
        payout += deal.producerResponsibility;
    }

    storage.save();
    pay(deal.producer, payout);
}

fun handleProducerGiveUpDeal(sender: address, msg: ProducerGiveUpDeal) {
    var storage = lazy Storage.load();
    val deal = loadDeal(storage, msg.id);

    assert (sender == deal.producer) throw Errors.NotProducer;

    storage.deals.delete(msg.id);
    storage.totalClientMoney -= deal.amount;

    var payout = deal.amount;
    if (deal.producerPaid) {
        storage.totalClientMoney -= deal.producerResponsibility;
        payout += deal.producerResponsibility;
    }

    storage.save();
    pay(deal.consumer, payout);
}

fun handleConsumerReturnMoneyDueToNotLockedResponsibility(
    sender: address,
    msg: ConsumerReturnMoneyDueToNotLockedResponsibility,
) {
    var storage = lazy Storage.load();
    val deal = loadDeal(storage, msg.id);

    assert (sender == deal.consumer) throw Errors.NotConsumer;
    assert (!deal.producerPaid && deal.producerResponsibility > 0) throw Errors.ProducerAlreadyPaid;

    storage.deals.delete(msg.id);
    storage.totalClientMoney -= deal.amount;
    storage.save();

    pay(deal.consumer, deal.amount);
}

fun handleJudgeDeal(sender: address, createdAt: uint32, msg: JudgeDeal) {
    var storage = lazy Storage.load();
    val deal = loadDeal(storage, msg.id);

    assert (sender == storage.judgeSystem) throw Errors.NotJudgeSystem;
    assert (deal.expirationTime < createdAt) throw Errors.DealNotExpired;

    storage.deals.delete(msg.id);
    storage.totalClientMoney -= deal.amount;

    var payout = deal.amount;
    if (deal.producerPaid) {
        storage.totalClientMoney -= deal.producerResponsibility;
        payout += deal.producerResponsibility;
    }

    storage.save();

    if (msg.isProducerFault) {
        pay(deal.consumer, payout);
    } else {
        pay(deal.producer, payout);
    }
}

fun handleSystemFailureWithdraw(sender: address, createdAt: uint32, msg: SystemFailureWithdraw) {
    var storage = lazy Storage.load();
    val deal = loadDeal(storage, msg.id);

    assert (sender == deal.consumer) throw Errors.NotConsumer;
    assert (
        deal.expirationTime + storage.systemFailureFreezeTime < createdAt
    ) throw Errors.FreezeTimeNotPassed;

    storage.deals.delete(msg.id);
    storage.totalClientMoney -= deal.amount;

    if (deal.producerPaid) {
        storage.totalClientMoney -= deal.producerResponsibility;
        storage.save();
        pay(deal.producer, deal.producerResponsibility);
        pay(deal.consumer, deal.amount);
    } else {
        storage.save();
        pay(deal.consumer, deal.amount);
    }
}

fun handleChangeMinimalDealAmount(sender: address, msg: ChangeMinimalDealAmount) {
    var storage = lazy Storage.load();
    assert (sender == storage.judgeSystem) throw Errors.NotJudgeSystem;
    storage.minimalDealAmount = msg.minimalDealAmount;
    storage.save();
}

fun handleChangeFeePart(sender: address, msg: ChangeFeePart) {
    var storage = lazy Storage.load();
    assert (sender == storage.judgeSystem) throw Errors.NotJudgeSystem;
    assert (msg.feePart > 0) throw Errors.InvalidFeePart;
    storage.feePart = msg.feePart;
    storage.save();
}

fun handleChangeSystemFailureFreezeTime(sender: address, msg: ChangeSystemFailureFreezeTime) {
    var storage = lazy Storage.load();
    assert (sender == storage.judgeSystem) throw Errors.NotJudgeSystem;
    storage.systemFailureFreezeTime = msg.systemFailureFreezeTime;
    storage.save();
}

fun handleChangeMinimalContractBalance(sender: address, msg: ChangeMinimalContractBalance) {
    var storage = lazy Storage.load();
    assert (sender == storage.judgeSystem) throw Errors.NotJudgeSystem;
    storage.minimalContractBalance = msg.minimalContractBalance;
    storage.save();
}

fun handleWithdrawSafe(sender: address) {
    var storage = lazy Storage.load();
    assert (sender == storage.judgeSystem) throw Errors.NotJudgeSystem;

    val balance = contract.getOriginalBalance();
    val reserved = storage.totalClientMoney + storage.minimalContractBalance;
    assert (balance > reserved) throw Errors.NothingToWithdraw;

    val amount = balance - reserved;
    assert (amount > 0) throw Errors.NothingToWithdraw;
    pay(storage.judgeSystem, amount);
}

fun loadDeal(storage: Storage, id: uint128): Deal {
    val r = storage.deals.get(id);
    assert (r.isFound) throw Errors.DealNotFound;
    return r.loadValue();
}

fun pay(to: address, amount: coins) {
    if (amount > 0) {
        createMessage({
            bounce: BounceMode.NoBounce,
            value: amount,
            dest: to,
        }).send(SEND_MODE_PAY_FEES_SEPARATELY | SEND_MODE_IGNORE_ERRORS);
    }
}

get fun getDeal(id: uint128): Deal {
    val storage = lazy Storage.load();
    return loadDeal(storage, id);
}

get fun balance(): coins {
    return contract.getOriginalBalance();
}

get fun feeFund(): coins {
    val storage = lazy Storage.load();
    return storage.feeFund;
}

get fun minimalDealAmount(): coins {
    val storage = lazy Storage.load();
    return storage.minimalDealAmount;
}

get fun feePart(): uint8 {
    val storage = lazy Storage.load();
    return storage.feePart;
}

get fun systemFailureFreezeTime(): uint64 {
    val storage = lazy Storage.load();
    return storage.systemFailureFreezeTime;
}

get fun minimalContractBalance(): coins {
    val storage = lazy Storage.load();
    return storage.minimalContractBalance;
}

get fun totalClientMoney(): coins {
    val storage = lazy Storage.load();
    return storage.totalClientMoney;
}

get fun judgeSystem(): address {
    val storage = lazy Storage.load();
    return storage.judgeSystem;
}
