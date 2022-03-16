import logging
import time
from brownie import Wei, reverts

LOGGER = logging.getLogger(__name__)

def pack_random(provider, a, add = 0):
    result = 0
    shift = 1
    trait_id = 0
    for t in a:
        trait_id += 1
        div = 0 # provider.getTraitWeightSum(trait_id) * 25
        weight = provider.getTraitWeight(trait_id)
        for i in range(len(weight)):
            if i == t: # selected trait
                result += div * shift
            div += weight[i] * 25

        shift *= div

    return hex(result + add * shift)

def test_trait_weight(accounts, roach_nft, GenomeProviderTest):
    provider = accounts[0].deploy(GenomeProviderTest, roach_nft)
    roach_nft.setGenomeProviderContract(provider)
    provider.setTraitWeight(1, [1,3,4,1], [5,2,1,1])
    provider.setTraitWeight(2, [1, 1], [1,1])
    provider.setTraitWeight(3, [1, 1, 1], [2,2,2])
    provider.setTraitWeight(4, [1], [2])
    provider.setTraitWeight(5, [1], [2])
    provider.setTraitWeight(6, [1], [2])

    assert provider.getTraitWeightSum(1) == 9, "Sum"
    assert provider.getTraitWeight(1) == [1,3,4,1], "Weight"
    assert provider.getTraitWeightMaxBonus(1) == [5,2,1,1], "Weight"

    # no bonus
    assert provider.getWeightedRandomTest(1, 0*25, 0) == 0
    assert provider.getWeightedRandomTest(1, 1*25, 0) == 1
    assert provider.getWeightedRandomTest(1, 2*25, 0) == 1
    assert provider.getWeightedRandomTest(1, 3*25, 0) == 1
    assert provider.getWeightedRandomTest(1, 4*25, 0) == 2
    assert provider.getWeightedRandomTest(1, 5*25, 0) == 2
    assert provider.getWeightedRandomTest(1, 6*25, 0) == 2
    assert provider.getWeightedRandomTest(1, 7*25, 0) == 2
    assert provider.getWeightedRandomTest(1, 8*25, 0) == 3
    assert provider.getWeightedRandomTest(1, 9*25, 0) == 0
    assert provider.getWeightedRandomTest(1, 10*25, 0) == 1

    # max bonus
    assert provider.getWeightedRandomTest(1, 0*25, 25) == 0
    assert provider.getWeightedRandomTest(1, 1*25, 25) == 0
    assert provider.getWeightedRandomTest(1, 2*25, 25) == 0
    assert provider.getWeightedRandomTest(1, 3*25, 25) == 0
    assert provider.getWeightedRandomTest(1, 4*25, 25) == 0
    assert provider.getWeightedRandomTest(1, 5*25, 25) == 1
    assert provider.getWeightedRandomTest(1, 6*25, 25) == 1
    assert provider.getWeightedRandomTest(1, 7*25, 25) == 2
    assert provider.getWeightedRandomTest(1, 8*25, 25) == 3
    assert provider.getWeightedRandomTest(1, 9*25, 25) == 0
    assert provider.getWeightedRandomTest(1, 10*25, 25) == 0

    # whole genome

    assert pack_random(provider, [0, 0, 0, 0, 0]) == "0x0"
    assert pack_random(provider, [1, 0, 0, 0, 0]) == "0x19"
    assert pack_random(provider, [2, 0, 0, 0, 0]) == "0x64"
    assert pack_random(provider, [3, 0, 0, 0, 0]) == "0xc8"
    assert pack_random(provider, [0, 1, 0, 0, 0]) == "0x15f9"

    assert provider.normalizeGenome(0, 0) == "0x0000000000000000000000000000000000000000000000000000000000000000"
    assert provider.normalizeGenome("0x19", 0) == "0x0001000000000000000000000000000000000000000000000000000000000000"
    assert provider.normalizeGenome("0xC8", 0) == "0x0003000000000000000000000000000000000000000000000000000000000000"

    assert provider.normalizeGenome(pack_random(provider, [0, 1, 0, 0, 0]), 0) == "0x0000010000000000000000000000000000000000000000000000000000000000"
    assert provider.normalizeGenome(pack_random(provider, [3, 1, 2, 0, 0]), 0) == "0x0003010200000000000000000000000000000000000000000000000000000000"

    # whole genome max bonus
    assert provider.normalizeGenome("0x64", 25) == "0x0000000000000000000000000000000000000000000000000000000000000000"

    # random tail
    assert provider.normalizeGenome(pack_random(provider, [2, 0, 0, 0, 0, 0], 23432523532), 0) == "0x000200000000000cefaf74050000000000000000000000000000000000000000"
    assert provider.normalizeGenome(pack_random(provider, [2, 0, 0, 0, 0, 0], 23432523532), 25) == "0x000000000000000cefaf74050000000000000000000000000000000000000000"
