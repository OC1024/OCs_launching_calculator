# OCs Launching Calculator

Choose any recipe to compare the mass of launching its inputs against launching
its outputs. Each item row shows the required amount, unit mass, and total mass.
Unchecked item rows are excluded from the matching total.

Fluid rows without a barrel alternative are displayed with zero launch mass and
cannot be selected. For fluids with a barrel alternative, the checkbox switches
between the direct fluid display (unchecked) and the calculated barrel display
(checked). The calculator uses the barrel recipe to determine how many barrels
are required.

The lower total determines the launch recommendation. The number formatting
setting controls displayed amounts where rounding is useful; mass values retain
their direct runtime values.

## Testing

Use `/ocs-launching-calculator-reset` in the in-game chat to clear your saved
calculator state. This removes the selected recipe, silo, rocket-parts recipe,
window position, minimised state, and saved row selections for your player, then
closes the calculator window if it is open.
