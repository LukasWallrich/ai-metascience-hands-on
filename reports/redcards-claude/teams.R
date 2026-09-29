# Place own estimates among the 29 teams' ORs (run after analysis.R)
suppressPackageStartupMessages({library(data.table); library(ggplot2)})
t <- fread("teams_estimates.csv"); o <- fread("results_own.csv")
t <- t[, .(label = paste("Team", Team), OR, lo = OR_lo, hi = OR_hi, src = "29 teams")]
o <- o[, .(label = model, OR, lo, hi, src = ifelse(model == "Main", "This analysis: main", "This analysis: variants"))]
a <- rbind(t, o)[order(OR)]; a[, label := factor(label, label)]
cat("Teams median OR:", median(t$OR), " range:", range(t$OR), "\n")
cat("Teams with OR below own main (", o[src != "29 teams" & label == "Main", OR], "):", sum(t$OR < o[label == "Main", OR]), "of", nrow(t), "\n")
cat("Teams whose CI excludes 1:", sum(t$lo > 1), "\n")
p <- ggplot(a, aes(OR, label, colour = src)) + geom_vline(xintercept = 1, linetype = 2, colour = "grey50") +
  geom_errorbar(aes(xmin = lo, xmax = hi), width = 0, orientation = "y") + geom_point() +
  scale_x_log10() + coord_cartesian(xlim = c(0.5, 3)) +
  scale_colour_manual(values = c("grey55", "#c0392b", "#2e86c1")) +
  labs(x = "Odds ratio (log scale, 95% CI; axis clipped at 0.5-3)", y = NULL, colour = NULL) +
  theme_minimal(10) + theme(legend.position = "top")
ggsave("fig_teams.png", p, width = 7, height = 8, dpi = 150)
