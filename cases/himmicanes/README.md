# Case A: "Female hurricanes are deadlier than male hurricanes"

Jung, K., Shavitt, S., Viswanathan, M., & Hilbe, J. M. (2014). Female hurricanes are
deadlier than male hurricanes. *PNAS, 111*(24), 8782–8787.
https://doi.org/10.1073/pnas.1402786111

The paper reports that hurricanes with more feminine names cause more deaths, and
explains this with people taking feminine-named storms less seriously.

## Data

`hurricanes.csv`: 92 Atlantic hurricanes that made landfall in the US, 1950–2012,
as used in the paper. This copy is the `hurricanes` dataset distributed with the
DHARMa R package (GPL-3), exported to CSV.

| Variable | Meaning |
|---|---|
| `Year` | Year of the hurricane |
| `Name` | Name of the hurricane |
| `MasFem` | Masculinity–femininity rating of the name (1 = very masculine, 11 = very feminine) |
| `MinPressure_before` | Minimum air pressure, as in the original data |
| `Minpressure_Updated_2014` | Minimum air pressure, updated values |
| `Gender_MF` | Binary name gender (0 = male, 1 = female) |
| `Category` | Hurricane category |
| `alldeaths` | Number of deaths |
| `NDAM` | Normalised damage in millions of US dollars (2013 values) |
| `Elapsed_Yrs` | Years elapsed since the hurricane |
| `Source` | Source of the record (MWR or Wikipedia) |
| `ZMasFem`, `ZMinPressure_A`, `ZNDAM` | Standardised versions of `MasFem`, `MinPressure_before` and `NDAM` |
