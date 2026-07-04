import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/types"
import "@wrappers/SolomonDeal.gen"

const DEAL_ID = 1
const AMOUNT = 1_000_000_000
const FEE = 20_000_000
const RESPONSIBILITY = 100_000_000
const MAKE_VALUE = 1_070_000_000
const GAS_VALUE = 50_000_000
const FUTURE_TIME = 4_000_000_000

get fun `test make deal stores escrow state`() {
    val (contract, _, consumer, producer, _) = setupTest(1);

    val beforeContractBalance = testing.getAccountBalance(contract.address);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);

    val deal = contract.getDeal(DEAL_ID);
    expect(deal.consumer).toEqual(consumer.address);
    expect(deal.producer).toEqual(producer.address);
    expect(deal.amount).toEqual(AMOUNT);
    expect(deal.producerResponsibility).toEqual(RESPONSIBILITY);
    expect(deal.expirationTime).toEqual(FUTURE_TIME);
    expect(deal.producerPaid).toEqual(false);
    expect(contract.totalClientMoney()).toEqual(AMOUNT);
    expect(contract.feeFund()).toEqual(FEE);
    expect(testing.getAccountBalance(contract.address)).toBeGreater(beforeContractBalance);
}

get fun `test make deal rejects duplicate id`() {
    val (contract, _, consumer, producer, _) = setupTest(2);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);

    val res = sendMakeDeal(
        contract,
        consumer.address,
        producer.address,
        DEAL_ID,
        AMOUNT,
        FEE,
        MAKE_VALUE,
    );

    expect(res).toHaveFailedTx({
        from: consumer.address,
        to: contract.address,
        exitCode: Errors.DealAlreadyExists,
    });
}

get fun `test make deal rejects amount below minimum`() {
    val (contract, _, consumer, producer, _) = setupTest(3);

    val res = sendMakeDeal(
        contract,
        consumer.address,
        producer.address,
        DEAL_ID,
        ton("0.05"),
        ton("0.001"),
        ton("0.2"),
    );

    expect(res).toHaveFailedTx({
        from: consumer.address,
        to: contract.address,
        exitCode: Errors.InvalidAmount,
    });
    expect(contract.totalClientMoney()).toEqual(0);
}

get fun `test make deal rejects wrong fee`() {
    val (contract, _, consumer, producer, _) = setupTest(4);

    val res = sendMakeDeal(
        contract,
        consumer.address,
        producer.address,
        DEAL_ID,
        AMOUNT,
        FEE + 1,
        MAKE_VALUE,
    );

    expect(res).toHaveFailedTx({
        from: consumer.address,
        to: contract.address,
        exitCode: Errors.InvalidFee,
    });
    expect(contract.feeFund()).toEqual(0);
}

get fun `test make deal rejects insufficient attached value`() {
    val (contract, _, consumer, producer, _) = setupTest(5);

    val res = sendMakeDeal(
        contract,
        consumer.address,
        producer.address,
        DEAL_ID,
        AMOUNT,
        FEE,
        AMOUNT + FEE,
    );

    expect(res).toHaveFailedTx({
        from: consumer.address,
        to: contract.address,
        exitCode: Errors.InvalidAmount,
    });
    expect(contract.totalClientMoney()).toEqual(0);
}

get fun `test producer pays responsibility`() {
    val (contract, _, consumer, producer, _) = setupTest(6);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);

    val res = payResponsibility(contract, producer.address, DEAL_ID);

    expect(res).toHaveSuccessfulTx<PayResponsibility>({
        from: producer.address,
        to: contract.address,
    });

    val deal = contract.getDeal(DEAL_ID);
    expect(deal.producerPaid).toEqual(true);
    expect(contract.totalClientMoney()).toEqual(AMOUNT + RESPONSIBILITY);
}

get fun `test pay responsibility rejects wrong sender`() {
    val (contract, _, consumer, producer, stranger) = setupTest(7);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);

    val res = payResponsibility(contract, stranger.address, DEAL_ID);

    expect(res).toHaveFailedTx({
        from: stranger.address,
        to: contract.address,
        exitCode: Errors.NotProducer,
    });
    expect(contract.totalClientMoney()).toEqual(AMOUNT);
}

get fun `test pay responsibility rejects insufficient value`() {
    val (contract, _, consumer, producer, _) = setupTest(8);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);

    val res = contract.sendPayResponsibility(
        producer.address,
        DEAL_ID,
        { value: RESPONSIBILITY - 1 },
    );

    expect(res).toHaveFailedTx({
        from: producer.address,
        to: contract.address,
        exitCode: Errors.InvalidResponsibility,
    });

    val deal = contract.getDeal(DEAL_ID);
    expect(deal.producerPaid).toEqual(false);
    expect(contract.totalClientMoney()).toEqual(AMOUNT);
}

get fun `test pay responsibility rejects second payment`() {
    val (contract, _, consumer, producer, _) = setupTest(9);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);
    payResponsibility(contract, producer.address, DEAL_ID);

    val res = payResponsibility(contract, producer.address, DEAL_ID);

    expect(res).toHaveFailedTx({
        from: producer.address,
        to: contract.address,
        exitCode: Errors.ProducerAlreadyPaid,
    });
}

get fun `test complete deal without responsibility pays amount to producer`() {
    val (contract, _, consumer, producer, _) = setupTest(10);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);

    val producerBefore = testing.getAccountBalance(producer.address);
    val res = contract.sendCompleteTheDeal(consumer.address, DEAL_ID, { value: GAS_VALUE });

    expect(res).toHaveSuccessfulTx<CompleteTheDeal>({
        from: consumer.address,
        to: contract.address,
    });
    expectPayout(res, contract.address, producer.address, AMOUNT);
    expectBalanceIncrease(producer.address, producerBefore, AMOUNT);
    expect(contract.totalClientMoney()).toEqual(0);
}

get fun `test complete deal with responsibility pays amount plus responsibility to producer`() {
    val (contract, _, consumer, producer, _) = setupTest(11);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);
    payResponsibility(contract, producer.address, DEAL_ID);

    val producerBefore = testing.getAccountBalance(producer.address);
    val res = contract.sendCompleteTheDeal(consumer.address, DEAL_ID, { value: GAS_VALUE });

    expect(res).toHaveSuccessfulTx<CompleteTheDeal>({
        from: consumer.address,
        to: contract.address,
    });
    expectPayout(res, contract.address, producer.address, AMOUNT + RESPONSIBILITY);
    expectBalanceIncrease(producer.address, producerBefore, AMOUNT + RESPONSIBILITY);
    expect(contract.totalClientMoney()).toEqual(0);
}

get fun `test complete deal rejects unauthorized sender`() {
    val (contract, _, consumer, producer, stranger) = setupTest(12);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);

    val res = contract.sendCompleteTheDeal(stranger.address, DEAL_ID, { value: GAS_VALUE });

    expect(res).toHaveFailedTx({
        from: stranger.address,
        to: contract.address,
        exitCode: Errors.Unauthorized,
    });
    expect(contract.totalClientMoney()).toEqual(AMOUNT);
}

get fun `test judge can complete deal and pays producer`() {
    val (contract, judge, consumer, producer, _) = setupTest(13);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);

    val producerBefore = testing.getAccountBalance(producer.address);
    val res = contract.sendCompleteTheDeal(judge.address, DEAL_ID, { value: GAS_VALUE });

    expect(res).toHaveSuccessfulTx<CompleteTheDeal>({
        from: judge.address,
        to: contract.address,
    });
    expectPayout(res, contract.address, producer.address, AMOUNT);
    expectBalanceIncrease(producer.address, producerBefore, AMOUNT);
}

get fun `test complete deal pays inactive producer address`() {
    val (contract, _, consumer, producer, _) = setupTest(14);
    val inactiveProducer = inactiveAddress(1401, consumer.address);
    expect(testing.isDeployed(inactiveProducer)).toEqual(false);
    expect(testing.getAccountBalance(inactiveProducer)).toEqual(0);

    makeDeal(contract, consumer.address, inactiveProducer, DEAL_ID);

    val res = contract.sendCompleteTheDeal(consumer.address, DEAL_ID, { value: GAS_VALUE });

    expect(res).toHaveSuccessfulTx<CompleteTheDeal>({
        from: consumer.address,
        to: contract.address,
    });
    expectInactivePayout(res, contract.address, inactiveProducer, AMOUNT);
    expectInactiveBalanceIncrease(inactiveProducer, AMOUNT);
    expect(testing.isDeployed(inactiveProducer)).toEqual(false);
    expect(contract.totalClientMoney()).toEqual(0);
}

get fun `test judge resolution pays inactive producer address`() {
    val (contract, judge, consumer, producer, _) = setupTest(15);
    val inactiveProducer = inactiveAddress(1501, judge.address);
    expect(testing.isDeployed(inactiveProducer)).toEqual(false);
    expect(testing.getAccountBalance(inactiveProducer)).toEqual(0);

    makeExpiredDeal(contract, consumer.address, inactiveProducer, DEAL_ID);

    val res = contract.sendJudgeDeal(judge.address, DEAL_ID, false, { value: GAS_VALUE });

    expect(res).toHaveSuccessfulTx<JudgeDeal>({
        from: judge.address,
        to: contract.address,
    });
    expectInactivePayout(res, contract.address, inactiveProducer, AMOUNT);
    expectInactiveBalanceIncrease(inactiveProducer, AMOUNT);
    expect(testing.isDeployed(inactiveProducer)).toEqual(false);
    expect(contract.totalClientMoney()).toEqual(0);
}

get fun `test producer give up without responsibility pays amount to consumer`() {
    val (contract, _, consumer, producer, _) = setupTest(16);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);

    val consumerBefore = testing.getAccountBalance(consumer.address);
    val res = contract.sendProducerGiveUpDeal(producer.address, DEAL_ID, { value: GAS_VALUE });

    expect(res).toHaveSuccessfulTx<ProducerGiveUpDeal>({
        from: producer.address,
        to: contract.address,
    });
    expectPayout(res, contract.address, consumer.address, AMOUNT);
    expectBalanceIncrease(consumer.address, consumerBefore, AMOUNT);
    expect(contract.totalClientMoney()).toEqual(0);
}

get fun `test producer give up with responsibility pays amount plus responsibility to consumer`() {
    val (contract, _, consumer, producer, _) = setupTest(17);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);
    payResponsibility(contract, producer.address, DEAL_ID);

    val consumerBefore = testing.getAccountBalance(consumer.address);
    val res = contract.sendProducerGiveUpDeal(producer.address, DEAL_ID, { value: GAS_VALUE });

    expect(res).toHaveSuccessfulTx<ProducerGiveUpDeal>({
        from: producer.address,
        to: contract.address,
    });
    expectPayout(res, contract.address, consumer.address, AMOUNT + RESPONSIBILITY);
    expectBalanceIncrease(consumer.address, consumerBefore, AMOUNT + RESPONSIBILITY);
    expect(contract.totalClientMoney()).toEqual(0);
}

get fun `test producer give up rejects non producer`() {
    val (contract, _, consumer, producer, stranger) = setupTest(18);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);

    val res = contract.sendProducerGiveUpDeal(stranger.address, DEAL_ID, { value: GAS_VALUE });

    expect(res).toHaveFailedTx({
        from: stranger.address,
        to: contract.address,
        exitCode: Errors.NotProducer,
    });
}

get fun `test consumer return before responsibility pays amount back`() {
    val (contract, _, consumer, producer, _) = setupTest(19);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);

    val res = contract.sendConsumerReturnMoneyDueToNotLockedResponsibility(
        consumer.address,
        DEAL_ID,
        { value: GAS_VALUE },
    );

    expect(res).toHaveSuccessfulTx<ConsumerReturnMoneyDueToNotLockedResponsibility>({
        from: consumer.address,
        to: contract.address,
    });
    expectPayout(res, contract.address, consumer.address, AMOUNT);
    expect(contract.totalClientMoney()).toEqual(0);
}

get fun `test consumer return rejects after responsibility paid`() {
    val (contract, _, consumer, producer, _) = setupTest(20);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);
    payResponsibility(contract, producer.address, DEAL_ID);

    val res = contract.sendConsumerReturnMoneyDueToNotLockedResponsibility(
        consumer.address,
        DEAL_ID,
        { value: GAS_VALUE },
    );

    expect(res).toHaveFailedTx({
        from: consumer.address,
        to: contract.address,
        exitCode: Errors.ProducerAlreadyPaid,
    });
    expect(contract.totalClientMoney()).toEqual(AMOUNT + RESPONSIBILITY);
}

get fun `test consumer return rejects non consumer`() {
    val (contract, _, consumer, producer, stranger) = setupTest(21);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);

    val res = contract.sendConsumerReturnMoneyDueToNotLockedResponsibility(
        stranger.address,
        DEAL_ID,
        { value: GAS_VALUE },
    );

    expect(res).toHaveFailedTx({
        from: stranger.address,
        to: contract.address,
        exitCode: Errors.NotConsumer,
    });
}

get fun `test judge resolves unpaid expired deal in favor of consumer`() {
    val (contract, judge, consumer, producer, _) = setupTest(22);
    makeExpiredDeal(contract, consumer.address, producer.address, DEAL_ID);

    val consumerBefore = testing.getAccountBalance(consumer.address);
    val res = contract.sendJudgeDeal(judge.address, DEAL_ID, true, { value: GAS_VALUE });

    expect(res).toHaveSuccessfulTx<JudgeDeal>({
        from: judge.address,
        to: contract.address,
    });
    expectPayout(res, contract.address, consumer.address, AMOUNT);
    expectBalanceIncrease(consumer.address, consumerBefore, AMOUNT);
    expect(contract.totalClientMoney()).toEqual(0);
}

get fun `test judge resolves paid expired deal in favor of consumer`() {
    val (contract, judge, consumer, producer, _) = setupTest(23);
    makeExpiredDeal(contract, consumer.address, producer.address, DEAL_ID);
    payResponsibility(contract, producer.address, DEAL_ID);

    val consumerBefore = testing.getAccountBalance(consumer.address);
    val res = contract.sendJudgeDeal(judge.address, DEAL_ID, true, { value: GAS_VALUE });

    expectPayout(res, contract.address, consumer.address, AMOUNT + RESPONSIBILITY);
    expectBalanceIncrease(consumer.address, consumerBefore, AMOUNT + RESPONSIBILITY);
    expect(contract.totalClientMoney()).toEqual(0);
}

get fun `test judge resolves unpaid expired deal in favor of producer`() {
    val (contract, judge, consumer, producer, _) = setupTest(24);
    makeExpiredDeal(contract, consumer.address, producer.address, DEAL_ID);

    val producerBefore = testing.getAccountBalance(producer.address);
    val res = contract.sendJudgeDeal(judge.address, DEAL_ID, false, { value: GAS_VALUE });

    expectPayout(res, contract.address, producer.address, AMOUNT);
    expectBalanceIncrease(producer.address, producerBefore, AMOUNT);
    expect(contract.totalClientMoney()).toEqual(0);
}

get fun `test judge resolves paid expired deal in favor of producer`() {
    val (contract, judge, consumer, producer, _) = setupTest(25);
    makeExpiredDeal(contract, consumer.address, producer.address, DEAL_ID);
    payResponsibility(contract, producer.address, DEAL_ID);

    val producerBefore = testing.getAccountBalance(producer.address);
    val res = contract.sendJudgeDeal(judge.address, DEAL_ID, false, { value: GAS_VALUE });

    expectPayout(res, contract.address, producer.address, AMOUNT + RESPONSIBILITY);
    expectBalanceIncrease(producer.address, producerBefore, AMOUNT + RESPONSIBILITY);
    expect(contract.totalClientMoney()).toEqual(0);
}

get fun `test judge deal rejects non judge`() {
    val (contract, _, consumer, producer, stranger) = setupTest(26);
    makeExpiredDeal(contract, consumer.address, producer.address, DEAL_ID);

    val res = contract.sendJudgeDeal(stranger.address, DEAL_ID, true, { value: GAS_VALUE });

    expect(res).toHaveFailedTx({
        from: stranger.address,
        to: contract.address,
        exitCode: Errors.NotJudgeSystem,
    });
}

get fun `test judge deal rejects non expired deal`() {
    val (contract, judge, consumer, producer, _) = setupTest(27);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);

    val res = contract.sendJudgeDeal(judge.address, DEAL_ID, true, { value: GAS_VALUE });

    expect(res).toHaveFailedTx({
        from: judge.address,
        to: contract.address,
        exitCode: Errors.DealNotExpired,
    });
    expect(contract.totalClientMoney()).toEqual(AMOUNT);
}

get fun `test system failure withdraw unpaid deal returns amount to consumer`() {
    val (contract, judge, consumer, producer, _) = setupTest(28);
    makeExpiredDeal(contract, consumer.address, producer.address, DEAL_ID);
    setFreezeTime(contract, judge.address, 0);

    val res = contract.sendSystemFailureWithdraw(consumer.address, DEAL_ID, { value: GAS_VALUE });

    expect(res).toHaveSuccessfulTx<SystemFailureWithdraw>({
        from: consumer.address,
        to: contract.address,
    });
    expectPayout(res, contract.address, consumer.address, AMOUNT);
    expect(contract.totalClientMoney()).toEqual(0);
}

get fun `test system failure withdraw paid deal returns amount and responsibility`() {
    val (contract, judge, consumer, producer, _) = setupTest(29);
    makeExpiredDeal(contract, consumer.address, producer.address, DEAL_ID);
    payResponsibility(contract, producer.address, DEAL_ID);
    setFreezeTime(contract, judge.address, 0);

    val producerBefore = testing.getAccountBalance(producer.address);
    val res = contract.sendSystemFailureWithdraw(consumer.address, DEAL_ID, { value: GAS_VALUE });

    expect(res).toHaveSuccessfulTx<SystemFailureWithdraw>({
        from: consumer.address,
        to: contract.address,
    });
    expectPayout(res, contract.address, producer.address, RESPONSIBILITY);
    expectPayout(res, contract.address, consumer.address, AMOUNT);
    expectBalanceIncrease(producer.address, producerBefore, RESPONSIBILITY);
    expect(contract.totalClientMoney()).toEqual(0);
}

get fun `test system failure withdraw rejects non consumer`() {
    val (contract, judge, consumer, producer, stranger) = setupTest(30);
    makeExpiredDeal(contract, consumer.address, producer.address, DEAL_ID);
    setFreezeTime(contract, judge.address, 0);

    val res = contract.sendSystemFailureWithdraw(stranger.address, DEAL_ID, { value: GAS_VALUE });

    expect(res).toHaveFailedTx({
        from: stranger.address,
        to: contract.address,
        exitCode: Errors.NotConsumer,
    });
}

get fun `test system failure withdraw rejects before freeze time`() {
    val (contract, _, consumer, producer, _) = setupTest(31);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);

    val res = contract.sendSystemFailureWithdraw(consumer.address, DEAL_ID, { value: GAS_VALUE });

    expect(res).toHaveFailedTx({
        from: consumer.address,
        to: contract.address,
        exitCode: Errors.FreezeTimeNotPassed,
    });
}

get fun `test admin can update all settings`() {
    val (contract, judge, _, _, _) = setupTest(32);

    val minimalRes = contract.sendChangeMinimalDealAmount(
        judge.address,
        ton("0.2"),
        { value: GAS_VALUE },
    );
    val feePartRes = contract.sendChangeFeePart(judge.address, 25, { value: GAS_VALUE });
    val freezeRes = contract.sendChangeSystemFailureFreezeTime(
        judge.address,
        42,
        { value: GAS_VALUE },
    );
    val balanceRes = contract.sendChangeMinimalContractBalance(
        judge.address,
        ton("0.3"),
        { value: GAS_VALUE },
    );

    expect(minimalRes).toHaveSuccessfulTx<ChangeMinimalDealAmount>({
        from: judge.address,
        to: contract.address,
    });
    expect(feePartRes).toHaveSuccessfulTx<ChangeFeePart>({
        from: judge.address,
        to: contract.address,
    });
    expect(freezeRes).toHaveSuccessfulTx<ChangeSystemFailureFreezeTime>({
        from: judge.address,
        to: contract.address,
    });
    expect(balanceRes).toHaveSuccessfulTx<ChangeMinimalContractBalance>({
        from: judge.address,
        to: contract.address,
    });

    expect(contract.minimalDealAmount()).toEqual(ton("0.2"));
    expect(contract.feePart()).toEqual(25);
    expect(contract.systemFailureFreezeTime()).toEqual(42);
    expect(contract.minimalContractBalance()).toEqual(ton("0.3"));
}

get fun `test non admin cannot update settings`() {
    val (contract, _, consumer, _, _) = setupTest(33);

    expect(
        contract.sendChangeMinimalDealAmount(consumer.address, ton("0.2"), { value: GAS_VALUE }),
    ).toHaveFailedTx({
        from: consumer.address,
        to: contract.address,
        exitCode: Errors.NotJudgeSystem,
    });
    expect(contract.sendChangeFeePart(consumer.address, 25, { value: GAS_VALUE })).toHaveFailedTx({
        from: consumer.address,
        to: contract.address,
        exitCode: Errors.NotJudgeSystem,
    });
    expect(
        contract.sendChangeSystemFailureFreezeTime(consumer.address, 42, { value: GAS_VALUE }),
    ).toHaveFailedTx({
        from: consumer.address,
        to: contract.address,
        exitCode: Errors.NotJudgeSystem,
    });
    expect(
        contract.sendChangeMinimalContractBalance(
            consumer.address,
            ton("0.3"),
            { value: GAS_VALUE },
        ),
    ).toHaveFailedTx({
        from: consumer.address,
        to: contract.address,
        exitCode: Errors.NotJudgeSystem,
    });
}

get fun `test change fee part rejects zero`() {
    val (contract, judge, _, _, _) = setupTest(34);

    val res = contract.sendChangeFeePart(judge.address, 0, { value: GAS_VALUE });

    expect(res).toHaveFailedTx({
        from: judge.address,
        to: contract.address,
        exitCode: Errors.InvalidFeePart,
    });
    expect(contract.feePart()).toEqual(50);
}

get fun `test raw withdraw safe opcode is admin only and preserves client money`() {
    val (contract, judge, consumer, producer, _) = setupTest(35);
    makeDeal(contract, consumer.address, producer.address, DEAL_ID);

    val body = beginCell().storeUint(0, 32).storeSlice("withdraw safe".literalSlice()).endCell();

    val badRes = contract.sendAny(consumer.address, body, { value: GAS_VALUE });
    expect(badRes).toHaveFailedTx({
        from: consumer.address,
        to: contract.address,
        exitCode: Errors.NotJudgeSystem,
    });

    val res = contract.sendAny(judge.address, body, { value: GAS_VALUE });
    expect(res).toHaveSuccessfulTx({
        from: judge.address,
        to: contract.address,
    });
    expect(contract.totalClientMoney()).toEqual(AMOUNT);
}

get fun `test unknown opcode is rejected`() {
    val (contract, _, consumer, _, _) = setupTest(36);
    val body = beginCell().storeUint(0xdeadbeef, 32).endCell();

    val res = contract.sendAny(consumer.address, body, { value: GAS_VALUE });

    expect(res).toHaveFailedTx({
        from: consumer.address,
        to: contract.address,
        exitCode: Errors.InvalidMessage,
    });
}

get fun `test empty message is accepted as no op`() {
    val (contract, _, consumer, _, _) = setupTest(37);

    val res = contract.sendAny(consumer.address, createEmptyCell(), { value: GAS_VALUE });

    expect(res).toHaveSuccessfulTx({
        from: consumer.address,
        to: contract.address,
    });
}

get fun `test operations on missing deal fail with deal not found`() {
    val (contract, judge, consumer, producer, _) = setupTest(38);

    expect(
        contract.sendPayResponsibility(
            producer.address,
            DEAL_ID,
            { value: RESPONSIBILITY + GAS_VALUE },
        ),
    ).toHaveFailedTx({
        from: producer.address,
        to: contract.address,
        exitCode: Errors.DealNotFound,
    });
    expect(
        contract.sendCompleteTheDeal(consumer.address, DEAL_ID, { value: GAS_VALUE }),
    ).toHaveFailedTx({
        from: consumer.address,
        to: contract.address,
        exitCode: Errors.DealNotFound,
    });
    expect(
        contract.sendProducerGiveUpDeal(producer.address, DEAL_ID, { value: GAS_VALUE }),
    ).toHaveFailedTx({
        from: producer.address,
        to: contract.address,
        exitCode: Errors.DealNotFound,
    });
    expect(
        contract.sendJudgeDeal(judge.address, DEAL_ID, true, { value: GAS_VALUE }),
    ).toHaveFailedTx({
        from: judge.address,
        to: contract.address,
        exitCode: Errors.DealNotFound,
    });
}

fun setupTest(id: uint32): (SolomonDeal, Treasury, Treasury, Treasury, Treasury) {
    val judge = testing.treasury("judge");
    val consumer = testing.treasury("consumer");
    val producer = testing.treasury("producer");
    val stranger = testing.treasury("stranger");

    val contract = SolomonDeal.fromStorage(defaultStorage(id, judge.address));
    val res = contract.deploy(judge.address, { value: ton("2") });
    expect(res).toHaveSuccessfulDeploy({
        to: contract.address,
    });

    return (contract, judge, consumer, producer, stranger);
}

fun defaultStorage(id: uint32, judge: address): Storage {
    return {
        id,
        judgeSystem: judge,
        minimalDealAmount: ton("1"),
        feePart: 50,
        feeFund: 0,
        systemFailureFreezeTime: 864_000,
        minimalContractBalance: ton("0.1"),
        minimalAdditionAmountForFee: ton("0.01"),
        totalClientMoney: 0,
        deals: [],
    };
}

fun inactiveAddress(id: uint32, judge: address): address {
    return SolomonDeal.fromStorage(defaultStorage(id, judge)).address;
}

fun makeDeal(contract: SolomonDeal, consumer: address, producer: address, id: uint128) {
    makeDealWithExpiration(contract, consumer, producer, id, FUTURE_TIME);
}

fun makeExpiredDeal(contract: SolomonDeal, consumer: address, producer: address, id: uint128) {
    makeDealWithExpiration(contract, consumer, producer, id, 0);
}

fun makeDealWithExpiration(
    contract: SolomonDeal,
    consumer: address,
    producer: address,
    id: uint128,
    expirationTime: uint64,
) {
    val res = contract.sendMakeDeal(
        consumer,
        id,
        producer,
        RESPONSIBILITY,
        expirationTime,
        AMOUNT,
        FEE,
        { value: MAKE_VALUE },
    );

    expect(res).toHaveSuccessfulTx<MakeDeal>({
        from: consumer,
        to: contract.address,
    });
}

fun sendMakeDeal(
    contract: SolomonDeal,
    consumer: address,
    producer: address,
    id: uint128,
    amount: coins,
    fee: coins,
    value: coins,
): SendResultList {
    return contract.sendMakeDeal(
        consumer,
        id,
        producer,
        RESPONSIBILITY,
        FUTURE_TIME,
        amount,
        fee,
        { value },
    );
}

fun payResponsibility(contract: SolomonDeal, producer: address, id: uint128): SendResultList {
    return contract.sendPayResponsibility(producer, id, { value: RESPONSIBILITY + GAS_VALUE });
}

fun setFreezeTime(contract: SolomonDeal, judge: address, freezeTime: uint64) {
    val res = contract.sendChangeSystemFailureFreezeTime(judge, freezeTime, { value: GAS_VALUE });
    expect(res).toHaveSuccessfulTx<ChangeSystemFailureFreezeTime>({
        from: judge,
        to: contract.address,
    });
}

fun expectPayout(res: SendResultList, from: address, to: address, value: coins) {
    expect(res).toHaveSuccessfulTx({
        from,
        to,
        value,
    });
}

fun expectInactivePayout(res: SendResultList, from: address, to: address, value: coins) {
    expect(res).toHaveTx({
        from,
        to,
        value,
        success: false,
        bounced: false,
    });
}

fun expectBalanceIncrease(addr: address, before: coins, amount: coins) {
    val actual = testing.getAccountBalance(addr);
    expect(actual).toBeGreaterOrEqual(before + amount - ton("0.001"));
    expect(actual).toBeLessOrEqual(before + amount);
}

fun expectInactiveBalanceIncrease(addr: address, amount: coins) {
    val actual = testing.getAccountBalance(addr);
    expect(actual).toBeGreaterOrEqual(amount - ton("0.001"));
    expect(actual).toBeLessOrEqual(amount);
}
