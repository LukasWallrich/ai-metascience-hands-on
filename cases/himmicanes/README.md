# hurricanes.csv

This is the `hurricanes` dataset from the DHARMa R package (GPL-3), exported to CSV. The text below is the package's documentation of the dataset, unchanged.

A data set on hurricane strength and fatalities in the US between 1950 and 2012. The data originates from the study by Jung et al., PNAS, 2014, who claim that the masculinity / femininity of a hurricane name has a causal effect on fatalities, presumably through a different perception of danger caused by the names.

A 'data.frame': 93 obs. of  14 variables

- **Year**: Year of the hurricane (1950-2012)
- **Name**: Name of the hurricane
- **MasFem**: Masculinity-femininity rating of the hurricane's name in the range 1 = very masculine, 11 = very feminine
- **MinPressure_before**: Minimum air pressure (909-1002)
- **Minpressure_Updated_2014**: Updated minimum air pressure (909-1003)
- **Gender_MF**: Binary gender (male/female) based on MasFem (male = 0, female = 1)
- **Category**: Strength of the hurricane in categories (1:7). (1 = not at all, 7 = very intense)
- **alldeaths**: Deaths occured (1:256)
- **NDAM**: normalized damage in millions (1:75.000). The raw (dollar) amounts of property damage caused by hurricanes were obtained, and the unadjusted dollar amounts were normalized to 2013 monetary values by adjusting them to inflation, wealth and population density
- **Elapsed_Yrs**: elapsed since the occurrence of hurricanes (1:63)
- **Source**: MWR/wikipedia ()
- **ZMasFem**: scaled (MasFem)
- **ZMinPressure_A**: scaled (Minpressure_Updated_2014)
- **ZNDAM**: scaled (NDAM)
