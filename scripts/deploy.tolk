import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"

import "@contracts/types"
import "@wrappers/SolomonDeal.gen"

fun main(id: uint32 = 0) {
    val deployer = scripts.wallet("deployer");

    val contract = SolomonDeal.fromStorage({
        id,
        judgeSystem: deployer.address,
        minimalDealAmount: ton("0.1"),
        feePart: 50,
        feeFund: 0,
        systemFailureFreezeTime: 864_000,
        minimalContractBalance: ton("0.1"),
        minimalAdditionAmountForFee: ton("0.01"),
        totalClientMoney: 0,
        deals: [],
    });

    val res = contract.deploy(deployer.address, { value: ton("0.2") });
    println(res.waitForTrace());

    println("Deployed SolomonDeal id {} to {}", id, contract.address);
    println("Judge system is {}", contract.judgeSystem());
}
