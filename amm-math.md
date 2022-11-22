# Hyperdrive AMM Math

:::info
🚧 This document is a work in progress 🚧
:::

## Preliminaries

$z$ denotes the share reserves.

$y$ denotes the bond reserves.

$\mu$ denotes the initial price per share.

$c$ denotes the current share price.

$b_z$ denotes the share buffer.

$b_y$ denotes the bond buffer.

$\phi$ denotes the fee parameter.

$d_b$ denotes the days until maturity that all newly purchases bonds will be purchased at.

$t_{stretch}$ denotes the time stretch parameter.

$k$ is the yield space constant. For a given $\tau$, $k  = \frac{c}{\mu}(\mu z)^{1-\tau} + (y)^{1-\tau}$.

Given $d$ days until maturity, $t(d)$ = $\frac{d}{365}$.

Given $d$ days until maturity, $\tau(d) = \frac{t(d)}{t_{stretch}}$.

The AMM quotes the price of bonds in terms of base using the share reserves $z$, the bond reserves $y$, and a given amount of days until maturity $d$:

$$
p = (\frac{y}{\mu z})^{-\tau(d)}
$$

## Add Liquidity

Suppose an LP supplies $\Delta x$ base tokens. The amount of shares the LP is providing, $\Delta z$, is given by $\Delta z = \frac{\Delta x}{c}$.

### Reserves

The share reserves are updated as $z = z + \Delta z$.

Consider as motivating fact:

$$ \frac{y_{old}}{z_{old}} = \frac{y_{new}}{z_{new}} \implies p_{old} = p_{new} \implies r_{old} = r_{new} $$

Since we can calculate the current spot price from the reserves and share prices and the current APR from the current spot price, we can calculate the current pool APR $r$. We can substitute the updated share reserves $z = z + \Delta z$ to calculate the new bond reserves:

$$
y_{new} = y_{old} \cdot \frac {z+\Delta z}{z}$$

Upon initialization, either the initializer will either explicitly set the value of the bond reserves or they will provide a target interest rate that is used along with the share reserves to solve for the bond reserves:

$$
y = \mu z \cdot p^{\frac{-1}{\tau(d)}} = \mu z \cdot (1 - r
\cdot t(d))^{\frac{1}{\tau(d)}}
$$

### LP Tokens

When the LP token supply is equal to zero, the choice of LP tokens is arbitrary since the new LP will hold all of the LP tokens. In this case, the LP will receive LP tokens $\Delta l = \Delta x$. In all other cases, we must utilize an LP token calculation that ensures fairness for previous LPs. New LPs should be able to withdraw exactly the amount of base they contributed at the time of providing liquidity. Therefore, we need the new LP's maximum withdrawal amount to equal the capital that they put in.

From the "Remove Liquidity" section, the amount withdrawn for a given amount of LP tokens $\Delta l$ is:

$$
c \cdot (z - b_z) \cdot \frac{\Delta l}{l}
$$

Substituting in $z = z + \Delta z$ and $l = l + \Delta l$ and setting this equal to $c \cdot \Delta z$, we get:

$$
c \cdot \Delta z = c \cdot ((z + \Delta z) - b_z) \cdot \frac{\Delta l}{l + \Delta l}
$$

We can solve this for $\Delta l$, the new LP tokens:

$$
\Delta l = \frac{\Delta z \cdot l}{z - b_z}
$$

We update the LP balances so that $l_t$ (the LP balance of the trader providing liquidity) is $l_t = l_t + \Delta l$ and the global LP balance $l$ is $l = l + \Delta l$.

:::warning
**Note:** Refer to example 1 below
:::

## Remove Liquidity

Suppose a trader attempts to withdraw liquidity for an amount of LP tokens $\Delta l$. 

### Accounting

#### Withdrawal

Since this AMM uses a virtual reserves system for the bond reserves, an LP can only ever withdraw base assets. The total amount of withdrawable shares is $z - b_z$ as this is the maximum amount of shares that can be removed while still satisfying the invariant $z \geq b_z$. This implies that the total amount of base that can be withdrawn is given by $c(z - b_z)$. LP withdrawals are executed pro-rata given the amount $\Delta l$ of LP tokens being withdrawn. From this, the amount of base withdrawn by redeeming $\Delta l$ LP tokens is:

$$
\Delta x = c \cdot \Delta z = c \cdot (z - b_z) \cdot \frac{\Delta l}{l}
$$

#### LP tokens

First, we must ensure that the trader's LP token balance $l_t$ satisfies $l_t \geq \Delta l$. 

Next we update the trader's LP balance so that $l_t = l_t - \Delta l$ and the global LP balance $l$ so that $l = l - \Delta l$. 

#### Reserves

The share reserves are updated as $z = z - \Delta z$. 

The $y$ reserves are updated to maintain the current APR. Using the formula in the introduction, we simply preserve the reserve ratio to preserve the price.

$$
y_{new} = \frac{y_{old}(z - \Delta z)}{z}
$$

:::warning
**Note:** Refer to example 2 below
:::

## Buy

Suppose a trader requests to buy $\Delta x$ base worth of bonds. The trader will receive $\Delta y$ bonds maturing in $d_b$ days where $\Delta y$ is priced by the AMM curve.

### Pricing

We can immediately convert the base amount into the amount of shares the trader pays for bonds as $\Delta z = \frac{\Delta x}{c}$.

We must solve for $\Delta y$, the amount of bonds that the trader should receive. We'll start by solving for the change in $y$ without accounting for fees, $\Delta y'$. The YieldSpace invariant is given by:

$$
\frac{c}{\mu} \cdot (\mu \cdot (z + \Delta z))^{1 - \tau(d_b)} + (y - \Delta y')^{1 - \tau(d_b)} = k.
$$

Solving this for $\Delta y'$ yields:

$$
\Delta y' = y - (k - \frac{c}{\mu} \cdot (z + \Delta z)^{1-\tau(d_b)})^{\frac{1}{1-\tau(d_b)}}
$$

The fees for the purchase we charge on the interest implied by this purchase the face value of the bonds minus what was paid, $f$ are paid in bonds and are given by:

$$
f = \phi \cdot (\Delta y' - \Delta x)
$$

Now that we have $\Delta y'$ and $f$, we have that $\Delta y = \Delta y' - f$. 

### Accounting

The share reserves will be updated as $z = z + \Delta z$.

The bond reserves will be updated as $y = y - \Delta y$.

The share buffer will be updated as $b_z = b_z + \frac{\Delta y}{c}$. 

The bond buffer remains unchanged.

The trader will be charged $\Delta x$ base and sent $\Delta y$ bonds.

:::warning
**Note:** Refer to example 3 below
:::

## Sell

Suppose a trader requests to sell $\Delta y$ bonds maturing in $d$ days. Then the trader will receive $\Delta x$ base where $\Delta x$ is priced by the AMM curve.

### Pricing

The amount of base the trader receives is given by $\Delta x = c \cdot \Delta z$ where $\Delta z$ is the amount of shares the bonds are worth in the internal accounting.

We must solve for $\Delta z$, the amount of shares the trader should receive. We'll start by solving for the amount of shares the trader would receive without fees $\Delta z'$. The YieldSpace invariant is given by:

$$
\frac{c}{\mu} \cdot (\mu \cdot (z - \Delta z'))^{1 - \tau(d)} + (y + \Delta y)^{1 - \tau(d)} = k.
$$

Solving this for $\Delta z'$ yields:

$$
\Delta z' = z - \mu^{-1} \cdot (\frac{\mu}{c} \cdot (k - (y + \Delta y)^{1-\tau(d)}))^{\frac{1}{1-\tau(d)}}
$$

The fees for the sale, $f$, will be paid in the base asset and are given by:

$$
f = \phi \cdot (\Delta y - \Delta x) 
$$

Now that we have $\Delta z'$ and $f$, we can say that:

$$
\Delta x = c \cdot \Delta z' - f
$$

Since $\Delta x = c \cdot \Delta z$, we can also say that:

$$
\Delta z = \Delta z' - \frac{f}{c}
$$

### Accounting

The share reserves will be updated as $z = z - \Delta z$.

The bond reserves will be updated as $y = y + \Delta y$.

The share buffer will be updated as $b_z = b_z - \frac{\Delta y}{c}$. 

The bond buffer remains unchanged.

The trader will be charged $\Delta y$ bonds and sent $\Delta x$ base.

:::warning
**Note:** Refer to example 4 below
:::

## Open Short

Suppose a trader requests to short $\Delta y$ bonds maturing in $d_b$ days. The AMM will commit to pay the trader $\Delta z$ shares which will be converted to base when the trader closes the short where $\Delta z$ is priced by the AMM curve.

### Pricing

Using the pricing calculation outlined in the "Sell" section, the pricing model will output the number of shares $\Delta z$ that the bonds are worth. $\Delta x = c \cdot \Delta z$ and the system will store the agreed upon price.

### Accounting

The share reserves will be updated as $z = z - \Delta z$.

The bond reserves will be updated as $y = y + \Delta y$.

The base buffer remains unchanged. 

The bond buffer will be updated as $b_y = b_y + \Delta y$.


For the remainder of the accounting, we'll consider the accounting to be indexed by the trader and the block timestamp at the time of opening the short.

The trader will add base which will be converted to $\frac{\Delta y}{c} - \Delta z$ shares in their margin account to cover the maximum loss scenario.

The accounts receivable will be increased by $\Delta z$.

The accounts payable will be increased by $\Delta y$.

:::warning
**Note:** Refer to example 5 below
:::

## Close Short

Suppose a trader requests to close $\Delta y$ bonds of a short position that matures in $d$ days. Then the trader will purchase the $\Delta y$ bonds for the market price of $\Delta z$ shares. These bonds will then be sold back to the AMM for the price that was agreed to when the short was opened.

### Pricing

We must solve the YieldSpace invariant to find $\Delta z$. We'll start with solving for the shares that will be paid for the bonds without fees $\Delta z'$. The YieldSpace invariant is given by:

$$
\frac{c}{\mu} \cdot (\mu \cdot (z + \Delta z'))^{1 - \tau(d)} + (y - \Delta y) ^ {1 - \tau(d)} = k
$$

Solving this for $\Delta z'$ gives:

$$
\Delta z' = \mu^{-1} \cdot (\frac{\mu}{c} \cdot (k - (y - \Delta y)^{1 - \tau(d)}))^{\frac{1}{1 - \tau(d)}} - z
$$

Computing the fee for this purchase is more complicated than for other trades because attempting to use the same method yields a potentially intractable algebra problem (TODO: Continute trying to solve this). With this in mind, the following is a good approximation of the other fee calculations. 

$$
f = \phi \cdot (\Delta y - \Delta x) 
$$

Now that we have $\Delta z'$ and $f$, we can calculate that $\Delta z = \Delta z' + \frac{f}{c}$.

### Accounting

The share reserves will be updated as $z = z + \Delta z$.

The bond reserves will be updated as $y = y - \Delta y$.

The share buffer remains unchanged. 

The bond buffer will be updated as $b_y = b_y - \Delta y$.

For the remainder of the accounting, we'll consider the accounting to be indexed by the trader and the block timestamp at the time of opening the short.

The accounts receivable will be decreased by $\Delta z$.

The accounts payable will be decreased by $\Delta y$. In the event that the accounts payable balance reaches zero, the margin held for this positions plus the accounts receivable should be sent to the trader.

:::warning
Note: Refer to Example 6 below
:::

## Appendix

### Virtual Reserve Calculations

Hyperdrive's bond reserves are entirely virtual. Instead of actually holding bonds, it has the potential to mint new bonds at a fixed APR defined by the YieldSpace invariant using the base and bond reserves. With this in mind, we need a way to compute the bond reserves required for the pool to target a given APR.

Let $p$ denote the spot price of bonds in terms of base quoted by the AMM and $d$ denote a number of days until maturity. Then the APR $r$ can be defined as:

$$
r = \frac{1 - p}{p \cdot t(d)}
$$

:::warning
**Note:** Refer to example 7 below
:::

We can reformulate the equation for $r$ in terms of $p$ into an equation of $p$ in terms of $r$ as:

$$
p = 1 - r \cdot t(d)
$$

Combining this with our other expression for $p$, we find that:

$$
(\frac{y}{\mu z})^{-\tau(d)} = 1 - r \cdot t(d)
$$

Solving this for the bond reserves $y$, we find that the bond reserves need to target a rate of $r$ are given by:

$$
y = \mu z \cdot (1 - r \cdot t(d))^{\frac{-1}{\tau(d)}}
$$

:::warning
**Note:** Refer to example 8 below
:::

## Appendix

### Invariants

In each of our actions, we ensure that $z \geq b_z$ and that $y \geq b_y$. In the event that these invariants are violated, the implementation should revert any changes that were made while processing the action.



## Examples

### 1. Adding Liquidity

Let:
- $z = 100,000$ (share reserves of 100,000 currently worth 200,000 base)
- $b_z = 10,000$ (share buffer of 10,000)
- $y = 150,000$ (bond reserves of 150,000)
- $l = 100,000$ (LP token supply of 100,000)
- $\Delta z = 20,000$

Then we calculate the new y as 

$$ y_{new} = \frac{y_{old} \cdot (z + \Delta z)}{z} = \frac{150,000 \cdot (100,000 + 20,000)}{100,000} = 180,000 $$

The new LP shares are:

$$ \Delta l = \frac{\Delta z \cdot l}{z - b_z} = \frac{20,000 \cdot 100,000}{100,000 - 10,000} = 22,222.\overline{2} $$

The depositor was credited with 22,222. We confirm there's no loss on immediate withdraw:

$$ (z-b_z) \cdot \frac {\Delta l}{l} = 110,000 \cdot \frac{22,222}{122,222} = 19999.83$$


### 2. Removing Liquidity

> TODO

### 3. Buying PT

> TODO

### 4. Selling PT

> TODO

### 5. Opening a Short

> TODO

### 6. Closing a Short

> TODO

### 7. Current APR Calculation

Let $p^{-1} = 0.96$ (the price of one bond is 0.96 base), $d = 182.5$ (6 months remaining), and $t(d) = \frac{182.5}{365} = 0.5$. 
   
We can calculate the rate as $r = \frac{1 - 0.96}{0.96 \cdot 0.5} = 0.08\overline{3}$.
   
### 8. Calculating Bond Reserves

Let:
- $c = 2$ (1 share is worth 2 base)
- $\mu = 1.5$ (1 share was initially worth 1.5 base)
- $r = 0.05$ (an APR of 5%) 
- $d = 182.5$ (6 months until maturity)
- $z = 100,000$ (share reserves of 100,000 currently worth 200,000 base)
- $t_{stretch} = 22.1868770169$ (a time stretch targeting an APY of 5%)
- $t(d) = \frac{182.5}{365} = 0.5$ (term length of 6 months)
- $\tau(d) = \frac{t(d)}{t_{stretch}} = 0.02253584403$ (this follows from the choice of the other values)

$$
y = 1.5 \cdot 100,000 \cdot (1 - 0.05 \cdot 0.5)^{\frac{-1}{0.02253584403}} = 461315.17
$$


Then we have that the midpoint price is:

$$ p = (\frac{461315.17}{150000})^{-0.02253584403} = 0.975 $$

This gives an interest rate of just over 5%, because the purchase price of the bond is slighly less than 0.025 cents earned by the bond over the period.

$$ r = \frac{1 - p}{p \cdot t(d)} = \frac {0.025}{0.975 \cdot 0.5} = 0.05128205128 $$ 
