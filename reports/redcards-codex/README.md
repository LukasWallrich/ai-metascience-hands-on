# Case B: Do referees give more red cards to dark-skin-toned players?

Silberzahn, R., Uhlmann, E. L., Martin, D. P., et al. (2018). Many analysts, one data
set: Making transparent how variations in analytic choices affect results. *Advances
in Methods and Practices in Psychological Science, 1*(3), 337–356.
https://doi.org/10.1177/2515245917747646

In this project, 29 teams analysed the same dataset to answer one question: are soccer
referees more likely to give red cards to dark-skin-toned players than to
light-skin-toned players?

## Data

Download the dataset from the project's OSF page and unzip it into this folder:
https://osf.io/download/fv8c3/ (5 MB zip, contains `CrowdstormingDataJuly1st.csv`).

The file has 146,028 player–referee dyads: 2,053 players from the first male divisions
of England, Germany, France and Spain (2012–13 season) and the 3,147 referees they
played under across their careers. Each row counts the games and cards between one
player and one referee.

| Variable | Meaning |
|---|---|
| `playerShort`, `player` | Player ID and name |
| `club`, `leagueCountry` | Player's club and its country |
| `birthday`, `height`, `weight`, `position` | Player characteristics |
| `games`, `victories`, `ties`, `defeats`, `goals` | Counts within the player–referee dyad |
| `yellowCards`, `yellowReds`, `redCards` | Cards the player received from this referee |
| `photoID` | ID of the player photo (missing for 468 players) |
| `rater1`, `rater2` | Skin tone rated from the photo by two independent raters (5-point scale, very light to very dark; stored as 0–1) |
| `refNum`, `refCountry` | Anonymised referee ID and referee country ID |
| `meanIAT`, `nIAT`, `seIAT` | Implicit race bias in the referee's country (Project Implicit), with its sample size and standard error |
| `meanExp`, `nExp`, `seExp` | Explicit race bias in the referee's country, with its sample size and standard error |

The 29 teams' estimates are published at https://osf.io/download/fa743/. The prompt
asks the agent to look at them only after it has run its own analysis.
