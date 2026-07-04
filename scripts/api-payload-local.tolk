import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/assert"
import "@acton/testing/expect"

import "@contracts/types"
import "@wrappers/SolomonDeal.gen"

const SCENARIO_COMPLETE_WITH_RESPONSIBILITY = 1
const SCENARIO_COMPLETE_WITHOUT_RESPONSIBILITY = 2
const SCENARIO_PRODUCER_GIVE_UP_WITH_RESPONSIBILITY = 3
const SCENARIO_REFUND_NO_RESPONSIBILITY = 4
const SCENARIO_JUDGE_CONSUMER_RIGHT = 5
const SCENARIO_JUDGE_PRODUCER_RIGHT_WITH_RESPONSIBILITY = 6

const GAS_VALUE = 100_000_000

fun main(
    scenario: uint8,
    contractId: uint32,
    dealId: uint128,
    amount: coins,
    responsibility: coins,
    fee: coins,
    expirationTime: uint64,
) {
    val makeDealBody = requireCellEnv("MAKE_DEAL_BODY");

    val judge = testing.treasury("judge");
    val consumer = testing.treasury("consumer");
    val producer = testing.treasury("producer");

    val contract = SolomonDeal.fromStorage(defaultStorage(contractId, judge.address));
    deployContract(contract, judge.address);
    sendMakeDealAndAssert(
        contract,
        consumer.address,
        producer.address,
        makeDealBody,
        dealId,
        amount,
        responsibility,
        fee,
        expirationTime,
    );

    if (scenario == SCENARIO_COMPLETE_WITH_RESPONSIBILITY) {
        runCompleteWithResponsibility(
            contract,
            consumer.address,
            producer.address,
            dealId,
            amount,
            responsibility,
        );
    } else if (scenario == SCENARIO_COMPLETE_WITHOUT_RESPONSIBILITY) {
        runCompleteWithoutResponsibility(contract, consumer.address, producer.address, amount);
    } else if (scenario == SCENARIO_PRODUCER_GIVE_UP_WITH_RESPONSIBILITY) {
        runProducerGiveUpWithResponsibility(
            contract,
            consumer.address,
            producer.address,
            dealId,
            amount,
            responsibility,
        );
    } else if (scenario == SCENARIO_REFUND_NO_RESPONSIBILITY) {
        runRefundNoResponsibility(contract, consumer.address, amount);
    } else if (scenario == SCENARIO_JUDGE_CONSUMER_RIGHT) {
        runJudgeConsumerRight(contract, judge.address, consumer.address, amount);
    } else if (scenario == SCENARIO_JUDGE_PRODUCER_RIGHT_WITH_RESPONSIBILITY) {
        runJudgeProducerRightWithResponsibility(
            contract,
            judge.address,
            producer.address,
            dealId,
            amount,
            responsibility,
        );
    } else {
        Assert.fail("Unsupported integration scenario");
    }

    println("API_PAYLOAD_LOCAL_OK scenario={}", scenario);
}

fun deployContract(contract: SolomonDeal, judge: address) {
    val deployRes = contract.deploy(judge, { value: ton("2") });
    expect(deployRes).toHaveSuccessfulDeploy({
        to: contract.address,
    });
}

fun sendMakeDealAndAssert(
    contract: SolomonDeal,
    consumer: address,
    producer: address,
    makeDealBody: cell,
    dealId: uint128,
    amount: coins,
    responsibility: coins,
    fee: coins,
    expirationTime: uint64,
) {
    val makeRes = contract.sendAny(consumer, makeDealBody, { value: amount + fee + GAS_VALUE });
    expect(makeRes).toHaveSuccessfulTx<MakeDeal>({
        from: consumer,
        to: contract.address,
    });

    val deal = contract.getDeal(dealId);
    expect(deal.consumer).toEqual(consumer);
    expect(deal.producer).toEqual(producer);
    expect(deal.amount).toEqual(amount);
    expect(deal.producerResponsibility).toEqual(responsibility);
    expect(deal.expirationTime).toEqual(expirationTime);
    expect(deal.producerPaid).toEqual(false);
    expect(contract.totalClientMoney()).toEqual(amount);
    expect(contract.feeFund()).toEqual(fee);
}

fun runCompleteWithResponsibility(
    contract: SolomonDeal,
    consumer: address,
    producer: address,
    dealId: uint128,
    amount: coins,
    responsibility: coins,
) {
    sendPayResponsibilityAndAssert(contract, producer, dealId, amount, responsibility);

    val producerBefore = testing.getAccountBalance(producer);
    val completeRes = contract.sendAny(
        consumer,
        requireCellEnv("COMPLETE_BODY"),
        { value: GAS_VALUE },
    );
    expect(completeRes).toHaveSuccessfulTx<CompleteTheDeal>({
        from: consumer,
        to: contract.address,
    });
    expectPayout(completeRes, contract.address, producer, amount + responsibility);
    expectBalanceIncrease(producer, producerBefore, amount + responsibility);
    expect(contract.totalClientMoney()).toEqual(0);
}

fun runCompleteWithoutResponsibility(
    contract: SolomonDeal,
    consumer: address,
    producer: address,
    amount: coins,
) {
    val producerBefore = testing.getAccountBalance(producer);
    val completeRes = contract.sendAny(
        consumer,
        requireCellEnv("COMPLETE_BODY"),
        { value: GAS_VALUE },
    );
    expect(completeRes).toHaveSuccessfulTx<CompleteTheDeal>({
        from: consumer,
        to: contract.address,
    });
    expectPayout(completeRes, contract.address, producer, amount);
    expectBalanceIncrease(producer, producerBefore, amount);
    expect(contract.totalClientMoney()).toEqual(0);
}

fun runProducerGiveUpWithResponsibility(
    contract: SolomonDeal,
    consumer: address,
    producer: address,
    dealId: uint128,
    amount: coins,
    responsibility: coins,
) {
    sendPayResponsibilityAndAssert(contract, producer, dealId, amount, responsibility);

    val consumerBefore = testing.getAccountBalance(consumer);
    val giveUpRes = contract.sendAny(
        producer,
        requireCellEnv("GIVE_UP_BODY"),
        { value: GAS_VALUE },
    );
    expect(giveUpRes).toHaveSuccessfulTx<ProducerGiveUpDeal>({
        from: producer,
        to: contract.address,
    });
    expectPayout(giveUpRes, contract.address, consumer, amount + responsibility);
    expectBalanceIncrease(consumer, consumerBefore, amount + responsibility);
    expect(contract.totalClientMoney()).toEqual(0);
}

fun runRefundNoResponsibility(contract: SolomonDeal, consumer: address, amount: coins) {
    val consumerBefore = testing.getAccountBalance(consumer);
    val refundRes = contract.sendAny(
        consumer,
        requireCellEnv("REFUND_NO_RESPONSIBILITY_BODY"),
        { value: GAS_VALUE },
    );
    expect(refundRes).toHaveSuccessfulTx<ConsumerReturnMoneyDueToNotLockedResponsibility>({
        from: consumer,
        to: contract.address,
    });
    expectPayout(refundRes, contract.address, consumer, amount);
    expectBalanceIncrease(consumer, consumerBefore, amount);
    expect(contract.totalClientMoney()).toEqual(0);
}

fun runJudgeConsumerRight(contract: SolomonDeal, judge: address, consumer: address, amount: coins) {
    val consumerBefore = testing.getAccountBalance(consumer);
    val judgeRes = contract.sendAny(judge, requireCellEnv("JUDGE_DEAL_BODY"), { value: GAS_VALUE });
    expect(judgeRes).toHaveSuccessfulTx<JudgeDeal>({
        from: judge,
        to: contract.address,
    });
    expectPayout(judgeRes, contract.address, consumer, amount);
    expectBalanceIncrease(consumer, consumerBefore, amount);
    expect(contract.totalClientMoney()).toEqual(0);
}

fun runJudgeProducerRightWithResponsibility(
    contract: SolomonDeal,
    judge: address,
    producer: address,
    dealId: uint128,
    amount: coins,
    responsibility: coins,
) {
    sendPayResponsibilityAndAssert(contract, producer, dealId, amount, responsibility);

    val producerBefore = testing.getAccountBalance(producer);
    val judgeRes = contract.sendAny(judge, requireCellEnv("JUDGE_DEAL_BODY"), { value: GAS_VALUE });
    expect(judgeRes).toHaveSuccessfulTx<JudgeDeal>({
        from: judge,
        to: contract.address,
    });
    expectPayout(judgeRes, contract.address, producer, amount + responsibility);
    expectBalanceIncrease(producer, producerBefore, amount + responsibility);
    expect(contract.totalClientMoney()).toEqual(0);
}

fun sendPayResponsibilityAndAssert(
    contract: SolomonDeal,
    producer: address,
    dealId: uint128,
    amount: coins,
    responsibility: coins,
) {
    val payRes = contract.sendAny(
        producer,
        requireCellEnv("PAY_RESPONSIBILITY_BODY"),
        { value: responsibility + GAS_VALUE },
    );
    expect(payRes).toHaveSuccessfulTx<PayResponsibility>({
        from: producer,
        to: contract.address,
    });
    expect(contract.getDeal(dealId).producerPaid).toEqual(true);
    expect(contract.totalClientMoney()).toEqual(amount + responsibility);
}

fun expectPayout(res: SendResultList, from: address, to: address, value: coins) {
    expect(res).toHaveSuccessfulTx({
        from,
        to,
        value,
    });
}

fun expectBalanceIncrease(addr: address, before: coins, amount: coins) {
    val actual = testing.getAccountBalance(addr);
    expect(actual).toBeGreaterOrEqual(before + amount - ton("0.001"));
    expect(actual).toBeLessOrEqual(before + amount);
}

fun requireCellEnv(name: string): cell {
    val value = env<cell>(name);
    if (value == null) {
        Assert.fail("Missing or invalid cell env");
    }
    return value;
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
