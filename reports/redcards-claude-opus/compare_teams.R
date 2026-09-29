# Places this analysis among the 29 teams' estimates (Silberzahn et al., 2018).
# Run from this folder after robustness.R: Rscript compare_teams.R
# Downloads the team estimates from OSF if absent; writes teams_comparison.png.

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

if (!file.exists("teams_estimates_osf.csv"))
  download.file("https://osf.io/download/fa743/", "teams_estimates_osf.csv", mode = "wb")
teams <- fread("teams_estimates_osf.csv")
mine <- fread("robustness_estimates.csv")
stopifnot(nrow(teams) == 29)

cat("Effect-size units reported by teams:\n"); print(table(teams$Effect.size.units))
cat(sprintf("Team ORs: median %.2f, range %.2f-%.2f\n",
            median(teams$OR), min(teams$OR), max(teams$OR)))
cat(sprintf("Teams with 95%% CI lower bound > 1: %d of %d\n", sum(teams$OR_lo > 1), nrow(teams)))
primary <- mine[model == "Primary"]
cat(sprintf("Teams with OR below my primary (%.3f): %d; equal: %d; above: %d\n", primary$OR,
            sum(teams$OR < round(primary$OR, 2)), sum(teams$OR == round(primary$OR, 2)),
            sum(teams$OR > round(primary$OR, 2))))
cat(sprintf("My 11 estimates span %.2f-%.2f; teams inside that span: %d\n",
            min(mine$OR), max(mine$OR), sum(teams$OR >= min(mine$OR) & teams$OR <= max(mine$OR))))

# Figure: team estimates sorted by OR, with my primary and the span of my alternatives
x_lim <- c(0.5, 3.2)
teams[, lab := sprintf("Team %d (%s)", Team, Effect.size.units)]
teams[, lab := factor(lab, levels = lab[order(OR)])]
teams[, `:=`(lo_c = pmax(OR_lo, x_lim[1]), hi_c = pmin(OR_hi, x_lim[2]))]
p <- ggplot(teams, aes(OR, lab)) +
  annotate("rect", xmin = min(mine$OR), xmax = max(mine$OR), ymin = -Inf, ymax = Inf,
           fill = "#2a78d6", alpha = 0.12) +
  geom_vline(xintercept = primary$OR, colour = "#2a78d6", linewidth = 0.8) +
  geom_vline(xintercept = 1, colour = "#8a8984", linewidth = 0.4) +
  geom_errorbar(aes(xmin = lo_c, xmax = hi_c), width = 0, linewidth = 0.7,
                colour = "#52514e", orientation = "y") +
  geom_point(size = 2.2, colour = "#52514e") +
  geom_text(data = teams[OR_hi > x_lim[2]], aes(x = x_lim[2], label = "CI continues →"),
            hjust = 1, vjust = -0.6, size = 2.6, colour = "#52514e") +
  geom_text(data = teams[OR_lo < x_lim[1]], aes(x = x_lim[1], label = "← CI continues"),
            hjust = 0, vjust = -0.6, size = 2.6, colour = "#52514e") +
  annotate("text", x = primary$OR, y = 29.9, label = sprintf("My primary: %.2f", primary$OR),
           hjust = -0.05, size = 3.2, colour = "#2a78d6") +
  scale_x_log10(breaks = c(0.5, 0.75, 1, 1.5, 2, 3)) +
  coord_cartesian(xlim = x_lim, ylim = c(1, 30), clip = "off") +
  labs(x = "Odds ratio (log scale; team estimates as converted in the OSF file)", y = NULL,
       title = "The 29 teams' estimates and this analysis",
       subtitle = "Blue line: my primary estimate. Blue band: range of my 11 estimates (primary + 10 alternatives).") +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), panel.grid.major.y = element_blank(),
        plot.title.position = "plot")
ggsave("teams_comparison.png", p, width = 8, height = 7, dpi = 200, bg = "white")
