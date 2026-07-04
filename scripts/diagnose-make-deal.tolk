import "@acton/env"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/testing/assert"

import "@wrappers/SolomonDeal.gen"

fun main(contractAddress: address, consumerAddress: address, value: coins) {
    val contract = SolomonDeal.fromAddress(contractAddress);
    val body = requireCellEnv("MAKE_DEAL_BODY");

    println("Contract balance before: {}", contract.balance());
    println("Fee part: {}", contract.feePart());
    println("Sending value: {}", value);

    val result = contract.sendAny(consumerAddress, body, { value });
    println(result);
}

fun requireCellEnv(name: string): cell {
    val value = env<cell>(name);
    if (value == null) {
        Assert.fail("Missing or invalid cell env");
    }
    return value;
}
