import "@acton/emulation/testing"
import "@acton/io"

import "@contracts/types"
import "@wrappers/SolomonDeal.gen"

fun main(contractId: uint32) {
    val judge = testing.treasury("judge");
    val consumer = testing.treasury("consumer");
    val producer = testing.treasury("producer");
    val contract = SolomonDeal.fromStorage(defaultStorage(contractId, judge.address));

    println("API_CONTRACT={}", contract.address);
    println("API_JUDGE={}", judge.address);
    println("API_CONSUMER={}", consumer.address);
    println("API_PRODUCER={}", producer.address);
}

fun defaultStorage(id: uint32, judge: address): Storage {
    return {
        id,
        judgeSystem: judge,
        minimalDealAmount: ton("0.1"),
        feePart: 50,
        feeFund: 0,
        systemFailureFreezeTime: 864_000,
        minimalContractBalance: ton("0.1"),
        minimalAdditionAmountForFee: ton("0.01"),
        totalClientMoney: 0,
        deals: [],
    };
}
