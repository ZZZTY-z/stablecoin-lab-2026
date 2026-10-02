# STUDENT-QUESTIONS.md — Discussion questions (submit with your repo)

Answer directly under each question. 150–300 words each — **reasoning over length**.

---

## A. Permission design

**A1.** The vault holds `MINTER_ROLE`, so it can `burn` any user's balance. Explain why that is a risk, then write out how you would change `Vault` and `SimpleStablecoin` to remove it.

> Your answer:I think the main risk is that the vault holds MINTER_ROLE, so it can burn any user's balance. This means it has an almost unchecked power to move other people's tokens without their consent. As a result, users do not truly own their sUSD, and the whole system is not transparent or fair enough. The last two tests in Ex4 prove this point: test_Ex4_AttackerCannotBurnOthersBalance shows that an outsider without MINTER_ROLE cannot burn someone else's balance, but test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance shows that the vault holds this role and therefore can burn anyone's balance. So the problem is not that the permission check is written incorrectly; rather, the key was handed to the vault, while the guard itself is correct. My fix is to separate the burn permission from MINTER_ROLE. In SimpleStablecoin, add a burnFrom that requires the user to first approve an allowance to the vault. Then Vault.redeem lets the user approve first, and the vault calls burnFrom, so it can only burn the amount the user agreed to. Another approach is to let users burn their own tokens and then call the vault to retrieve the collateral. This way the vault cannot freely burn other people's balances. In addition, DEFAULT_ADMIN_ROLE should be given to a multi-sig with a timelock, not a regular address. The core idea is that the vault can continue to do what it should do, but it should not be given unlimited burn power.

<br><br><br>

**A2.** In this contract `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` all go to the same address. How would you split them in production, and who holds each?

> Your answer:DEFAULT_ADMIN_ROLE is the source of all permissions, since it can grant or revoke roles for anyone. For this reason, I would not assign it to a single creator; instead I would hand it to a multisig wallet or a governance contract, ideally with a timelock attached. Changing permissions would then require agreement from multiple parties and a waiting period, so no individual can act in secret. MINTER_ROLE should be granted only to the Vault contract itself, or to a minting module controlled by governance; no individual should hold it directly, because whoever holds it can mint tokens out of thin air. If a person must hold it at all, it should again be behind a multisig plus a timelock. PAUSER_ROLE, which is used to pause the system, I would give to a security committee — for example a multisig held by several engineers or auditors. Pausing needs to be fast, so the timelock can be short, but every pause must be recorded and monitorable. Once these roles are separated, the compromise of a single private key cannot simultaneously affect minting, pausing, and permission management, which greatly reduces the overall risk. The core principle is simple: the highest authority must not belong to an individual, minting power belongs to the contract, and pausing power belongs to a team.

<br><br><br>

---

## B. Pausing and redemption

**B1.** `_update` is the single entry point for every balance change, so `pause()` freezes transfers, minting and redemption together. If you wanted "pause transfers but **allow redemption**", how would you change it? Give the approach — full code not required.

> Your answer:Currently, _update is the only entry point for all balance changes, so once pause() is activated, transfers, minting, and redemptions are all frozen at once. To achieve "pause transfers but allow redemptions," the pause check cannot be placed inside _update as a blanket rule. My idea is that when the system is paused, only transfers between accounts should be frozen, while a user redeeming their own position should not be. Specifically, the pause check should be added only to transfer and transferFrom. Ordinary transfers would then be blocked, but burn and burnFrom would remain unaffected. During redemption, the user burns their own sUSD and the vault returns the collateral; since this process involves no transfer of sUSD between accounts, it can continue even while paused. A more flexible option is to introduce three separate switches: transfersPaused, mintingPaused, and burningPaused. In a crisis, only transfers would be halted while redemptions stay open, because redemption is precisely the channel through which the price returns to its peg — if it is frozen too, what started as a mere liquidity problem will quickly turn into a confidence problem.

<br><br><br>

**B2.** In 2008, when a money-market fund "broke the buck", redemptions were frozen for days. In 2023 USDC depegged to $0.87 after a reserve bank failed, but redemptions were **not** shut. Compare the two responses — what does closing the redemption channel, or leaving it open, do to a stablecoin?

> Your answer:After the money market fund froze redemptions in 2008, the result was not "reducing the shock" but terrifying everyone. Investors who could not get their money back assumed something terrible must have happened inside, panic intensified, and the fund ultimately broke the buck. Freezing redemptions is effectively telling the market: we can't hold on. Once reputation collapses, recovery becomes far harder. In 2023, USDC fell to $0.87 when one of its reserve banks ran into trouble, but redemptions stayed open. Arbitrageurs saw USDC trading at a discount, bought it, and redeemed it at $1 to capture the spread, and that buying pressure quickly pushed the price back to parity. Keeping the redemption channel open gave the market a credible promise that they could always exchange their tokens for a dollar, so the arbitrage mechanism could do its work. Comparing the two cases, closing the redemption channel may look like an attempt to stop a run, but in reality it destroys credibility and makes the panic worse. Keeping redemptions open means bearing short-term outflow pressure, yet it gives the market a stable expectation and lets arbitrageurs help push the price back toward the peg. For a stablecoin, the redemption channel is itself part of the pegging mechanism; shutting it down makes the peg more likely to break.

<br><br><br>

---

## C. Depeg analysis

**C1.** Under what conditions does this coin depeg? Distinguish at least two classes of cause, and say how each one shows up in the invariant `totalCollateral() >= totalSupply()`.

> Your answer:I think a stablecoin depegging can be traced to two distinct causes. The first is a solvency problem: the collateral is simply no longer worth enough. If the collateral price crashes until it can no longer back all the sUSD, the invariant totalCollateral() >= totalSupply() breaks. Each token then ceases to be fully backed and therefore loses its support. As I recall, 120% is a danger line—below it positions become eligible for liquidation—but a genuine depeg is more severe than that: the total value of collateral has already fallen below total supply. In that situation, no matter how redemptions proceed, someone will inevitably fail to get their money back. The second cause is a liquidity problem. Here the collateral still exists and the invariant totalCollateral() >= totalSupply() still holds, yet users cannot exchange their tokens for dollars—for example, because the vault lacks sufficient liquid assets or because redemptions have been paused. It is like a bank that holds plenty of long-term assets but not enough cash, so customers cannot withdraw when they arrive. The market price falls in this case too, but the reason is not "there is no money"; it is "you cannot reach the money." The collateral is there—it just cannot be turned into dollars immediately for the user. So the two types of depeg show up differently in the invariant: the first breaks the invariant, while the second keeps the invariant intact but blocks the redemption channel. Both drive the price off the peg, but they call for different remedies.

<br><br><br>

**C2.** Suppose an attacker bribes their way to `MINTER_ROLE`, mints 1,000,000 sUSD out of nothing and redeems it all. Describe the flow of funds, and name the step that could have stopped them.

> Your answer:An attacker first obtains MINTER_ROLE by bribing or hacking an admin. He then calls stable.mint(attacker, 1_000_000e6) and creates a million sUSD out of thin air. At this point the real money in the vault — the collateral — has not changed at all, but total supply has grown by a million. He then calls Vault.redeem(1_000_000e6), the vault burns those million sUSD and transfers the equivalent amount of USDC to him. If the vault holds enough USDC, he walks away with all of it; if not, the redemption reverts. Either way, the system either loses money or sees its peg broken.To use an analogy: the vault originally holds $10,000 against 10,000 sUSD, so each token is backed by one dollar. The attacker mints 1,000 extra sUSD, making 11,000 tokens backed by only $10,000. He then swaps those 1,000 tokens for $1,000, leaving 10,000 tokens backed by just $9,000. Nobody's coins are fully supported anymore — that is the depeg.What can stop him starts at grantRole: only an admin can assign MINTER_ROLE. In production, that admin should be a multisig plus timelock, so granting a role requires multiple signatures and a delay, giving monitoring systems time to detect and block it. A second line of defense is a check before mint or redeem verifying that totalCollateral() >= totalSupply() — after any minting, total supply must not exceed collateral value. Then even if someone mints secretly, redeem will revert because he cannot extract more than the collateral backs. Layered defenses reduce the damage when a permission leaks.

<br><br><br>

---

## D. Toward RWA

**D1.** Right now the collateral is `MockUSDC` and `totalCollateral()` just reads an on-chain balance — simple and reliable. If the collateral were **US Treasuries**, could this invariant still be written that way? What new problems appear?

> Your answer:You can't just read the on-chain balance the way MockUSDC does, because US Treasuries are off-chain assets. The vault doesn't hold them directly; it holds them through a custodian or broker, so the contract cannot call balanceOf to get the Treasury amount. Treasury prices also fluctuate — less than crypto, but they are not fixed at $1 — so totalCollateral() cannot simply read a balance; it must rely on an oracle or trusted reporter to tell the contract how many Treasuries are held and what they are worth. This introduces many new problems. First is custody risk: the custodian may fail, act maliciously, or have its keys compromised. Second is settlement delay: Treasury trades are not instant and may take T+1 or longer. Third is valuation: the oracle may be stale or manipulable. Fourth is liquidity: Treasuries are liquid but cannot be turned into cash in seconds. Fifth is legal ownership: who actually holds legal title to these Treasuries? Sixth is auditability: how do you prove the reserves really exist? So the invariant becomes something like reportedCollateralValue() >= totalSupply(), where the report comes from a trusted source. That imports an off-chain trust assumption that on-chain USDC does not have. To do it properly you need independent audits, proof of reserves, legal documentation, and probably multiple oracles. The invariant can still be written, but it is no longer "trustless"; it depends on off-chain verification and legal enforcement.

<br><br><br>

**D2.** If the collateral were **a building**, how would you put it inside this vault? Which off-chain roles or legal structures would you have to introduce?

> Your answer:Real estate cannot be placed on-chain directly, so the first step is to set up an off-chain legal entity — typically an SPV — that holds the property, and then have the SPV issue tokens representing equity or debt claims on it, which the vault accepts as collateral. In this way the chain ends up with something that stands for the house. The off-chain side requires quite a few roles: a custodian or trustee to hold legal title to the property; appraisers who periodically value it, since an oracle cannot know a house's worth on its own; insurers and property managers; lawyers handling securities and real-estate law; and if the tokens qualify as securities, a transfer agent plus KYC/AML compliance. The hardest parts are valuation and liquidation: real estate is illiquid and appraisals are infrequent, so the oracle can only accept periodic reports, which introduces lag and manipulation risk; if a borrower defaults, the vault cannot sell the house immediately, and liquidation may take months. Consequently the system's invariant must rest on trusted appraisers and legal process rather than real-time prices, making it a hybrid of on-chain tokens and off-chain legal enforcement. 

<br><br><br>

---

## E. Tests (Tier 1 required — this is Ex4)

Turn the red tests green in `test/exercises/01_LoopTasks.t.sol` to cover the scenarios below, and write your test function names here:

| Scenario | Your test function name |
|---|---|
| Minting by a non-minter reverts | |test_Ex4_Mint_RevertsForNonMinter
| Transfers revert while paused | |test_Ex4_Pause_BlocksTransfers
| **Redemption** reverts while paused | |test_Ex4_Pause_BlocksRedeem
| An attacker cannot burn someone else's balance | |test_Ex4_AttackerCannotBurnOthersBalance
| ...but the vault holding `MINTER_ROLE` can | |test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance

That last pair is meant to be read together: the guard is written correctly, but the key was handed to the vault. Keep it in mind when you answer A1.

Now write one more scenario you consider **most likely to be attacked**, and say why you picked it:

> Your answer:I think the most likely attack is an admin private key leak: because the admin holds DEFAULT_ADMIN_ROLE, it can call grantRole to hand out MINTER_ROLE to anyone. Once an attacker obtains the admin key, they can first grant themselves MINTER_ROLE, then call mint to create 1,000,000 sUSD out of thin air, and finally call redeem to swap those tokens for the USDC sitting in the vault. The permission checks in the code are not actually written incorrectly; the problem is that the attacker used admin authority to turn themselves into a "legitimate" minter, so every check passes without complaint. I chose this scenario precisely because it is a single point of failure: in the experiment the admin is just an Anvil private key, but in production, if that key lives in a hot wallet or on a server, or gets phished, the whole system is finished. Moreover, grantRole and mint both look like perfectly normal on-chain calls, so there is no immediate way to spot them. Defenses have to be layered: the admin should be a multisig rather than a single key; grantRole should carry a timelock to give monitoring systems time to react; alerts should fire on the RoleGranted event; minting should carry a total cap or a rate limit; and redeem should verify totalCollateral() >= totalSupply(). With these in place, even a leaked key makes it hard for an attacker to hollow out the system in one move.
