# 02_analysis.R
# Survey-weighted analysis of condom use at last sex among currently sexually
# active high school students (YRBS 2025): overall prevalence, cross-tabs with
# design-adjusted chi-square tests, and survey-weighted logistic regression.

library(dplyr)
library(survey)
library(ggplot2)

options(survey.lonely.psu = "adjust")
dir.create("results", showWarnings = FALSE)
dir.create("figures", showWarnings = FALSE)

d <- readRDS("data/yrbs2025_analysis.rds")

# ---- Survey design --------------------------------------------------------------
# Define the design on the full sample, then subset, so variance estimates use
# all strata and primary sampling units.
des    <- svydesign(id = ~psu, strata = ~stratum, weights = ~weight, nest = TRUE, data = d)
active <- subset(des, sexually_active %in% TRUE)
d_act  <- filter(d, sexually_active %in% TRUE)

# ---- Overall prevalence ------------------------------------------------------------
overall <- svymean(~condom, active, na.rm = TRUE)
cat("Weighted condom use:", round(100 * coef(overall), 1), "%  95% CI:",
    round(100 * confint(overall), 1), "\n")
cat("Unweighted condom use:", round(100 * mean(d_act$condom, na.rm = TRUE), 1), "%\n")

# ---- Table 1: weighted % by factor + Rao-Scott chi-square ---------------------
factors <- c("sex", "grade", "race", "identity", "alc_drugs", "partners4")
table1 <- do.call(rbind, lapply(factors, function(f) {
  est <- svyby(~condom, as.formula(paste0("~", f)), active, svymean, na.rm = TRUE)
  n   <- table(d_act[[f]])
  p   <- svychisq(as.formula(paste0("~condom + ", f)), active)$p.value
  data.frame(factor  = f,
             group   = as.character(est[[f]]),
             n       = as.integer(n[as.character(est[[f]])]),
             pct     = round(100 * est$condom, 1),
             ci_low  = round(100 * (est$condom - 1.96 * est$se), 1),
             ci_high = round(100 * (est$condom + 1.96 * est$se), 1),
             chisq_p = signif(unname(p), 3))
}))
print(table1)
write.csv(table1, "results/table1_condom_use_by_factor.csv", row.names = FALSE)

# ---- Table 2: survey-weighted logistic regression ----------------------------
model <- svyglm(condom ~ sex + grade + race + identity + alc_drugs + partners4,
                design = active, family = quasibinomial())
cat("Students in model (complete cases):", nobs(model), "\n")

or_table <- cbind(OR = exp(coef(model)), exp(confint(model)),
                  p = summary(model)$coefficients[, 4])
or_df <- data.frame(term = rownames(or_table), round(or_table, 3), row.names = NULL)
names(or_df) <- c("term", "OR", "ci_low", "ci_high", "p")
or_df <- or_df[or_df$term != "(Intercept)", ]
print(or_df)
write.csv(or_df, "results/table2_adjusted_odds_ratios.csv", row.names = FALSE)

# ---- Figure 1: forest plot of adjusted odds ratios ----------------------------
labels <- c(
  "sexMale" = "Male (vs female)",
  "grade10th" = "10th grade (vs 9th)", "grade11th" = "11th grade (vs 9th)",
  "grade12th" = "12th grade (vs 9th)",
  "raceBlack" = "Black (vs White)", "raceHispanic/Latino" = "Hispanic/Latino (vs White)",
  "raceAsian" = "Asian (vs White)", "raceMultiple (non-Hispanic)" = "Multiple race (vs White)",
  "raceOther" = "Other race (vs White)",
  "identityLGB or other" = "LGB or other (vs heterosexual)",
  "identityNot sure" = "Not sure (vs heterosexual)",
  "alc_drugsYes" = "Alcohol/drugs before sex",
  "partners44 or more" = "4+ lifetime partners")
or_df$label <- factor(labels[or_df$term], levels = rev(labels))
or_df$significant <- ifelse(or_df$ci_high < 1 | or_df$ci_low > 1, "Yes", "No")

fig1 <- ggplot(or_df, aes(x = OR, y = label, color = significant)) +
  geom_vline(xintercept = 1, linetype = "dashed", color = "gray50") +
  geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.2, orientation = "y") +
  geom_point(size = 2.5) +
  scale_x_log10() +
  scale_color_manual(values = c("No" = "gray60", "Yes" = "#1f4e79")) +
  labs(title = "Factors associated with condom use at last sex",
       subtitle = "Sexually active U.S. high school students, YRBS 2025 (weighted, adjusted)",
       x = "Adjusted odds ratio (log scale, 95% CI)", y = NULL,
       color = "Significant\n(p < 0.05)") +
  theme_minimal(base_size = 11)
ggsave("figures/figure1_forest_plot.png", fig1, width = 8, height = 5.5, dpi = 300)
