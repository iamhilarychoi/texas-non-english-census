### =========================================================
### Data Analytics Term Project
### Group 10: Seohyun Choi, Zitong Zhu
### Research Question: Among 52 regions (50 states + DC + Puerto Rico),
###                     what is Texas's rank in non-English speaking rate?
### Data: US Census Bureau, table B16001
###       (Language Spoken at Home by Ability to Speak English
###        for the Population 5 Years and Over), 2024 ACS 5-Year Estimates
### =========================================================

# install.packages('dplyr')
# install.packages('ggplot2')
# install.packages('tidyr')
# install.packages('ggrepel')
# install.packages('scales')

library(dplyr)
library(ggplot2)
library(tidyr)
library(ggrepel)
library(scales)

# Run this script from the repository root so that the relative paths
# ./data/ and ./output/ below resolve correctly, e.g.:
#   Rscript scripts/group10_analysis_final.R
# (in RStudio: set the working directory to the repo root first)
getwd()


### -----------------------------------------------------
### 1. Load Data
### -----------------------------------------------------

lang.dat <- read.csv("./data/language_by_state.csv",
                      header = TRUE,
                      check.names = FALSE,
                      stringsAsFactors = FALSE)

# as_tibble allows for nice printing (tbl_df() is deprecated/defunct in recent dplyr)
lang.dat <- as_tibble(lang.dat)

# Rename the first column (category label) for easier handling
# (Census CSVs exported from Excel often have a BOM before the first
#  column name, so we clean that up here too)
names(lang.dat)[1] <- "label"

lang.dat


### -----------------------------------------------------
### 2. Cleaning
### -----------------------------------------------------

# The Census CSV encodes its hierarchy using leading indentation
# (non-breaking spaces). We only need the "Total" row and the
# "Speak only English" row, since:
#   Non-English speaking population = Total - Speak only English

lang.dat <- lang.dat %>%
  mutate(label = sub("^[^A-Za-z]*", "", label),   # strip leading indentation (non-breaking space)
         label = trimws(label))

lang.clean <- lang.dat %>%
  filter(label %in% c("Total:", "Speak only English"))

lang.clean


### -----------------------------------------------------
### 3. Reshape Wide -> Long
### -----------------------------------------------------

# Margin of Error columns are not needed for this analysis
# (descriptive statistics + visualization), so keep Estimate columns only
lang.long <- lang.clean %>%
  select(label, ends_with("!!Estimate")) %>%
  pivot_longer(cols = -label,
               names_to = "state",
               values_to = "value") %>%
  mutate(state = gsub("!!Estimate", "", state),
         value = as.numeric(gsub(",", "", value)))

lang.long


### -----------------------------------------------------
### 4. Calculate Non-English Speaking Rate (%) by State
### -----------------------------------------------------

lang.wide <- lang.long %>%
  pivot_wider(names_from = label, values_from = value) %>%
  rename(total = `Total:`,
         english_only = `Speak only English`)

lang.ratio <- lang.wide %>%
  mutate(non_english = total - english_only,
         pct_non_english = round(non_english / total * 100, 2)) %>%
  select(state, total, english_only, non_english, pct_non_english)

lang.ratio


### -----------------------------------------------------
### 5. Ranking
### -----------------------------------------------------

lang.rank <- lang.ratio %>%
  arrange(desc(pct_non_english)) %>%
  mutate(rank = row_number()) %>%
  select(rank, state, pct_non_english, total, non_english)

lang.rank

# Check Texas's rank
texas.rank <- lang.rank %>%
  filter(state == "Texas")

texas.rank

cat(sprintf("Texas ranks #%d out of 52 regions in non-English speaking rate (%.2f%%)\n",
            texas.rank$rank, texas.rank$pct_non_english))


### -----------------------------------------------------
### 6. Descriptive Statistics
### -----------------------------------------------------

lang.rank %>%
  summarise(
    mean_pct   = mean(pct_non_english),
    median_pct = median(pct_non_english),
    sd_pct     = sd(pct_non_english),
    min_pct    = min(pct_non_english),
    max_pct    = max(pct_non_english)
  )

# What percentile does Texas fall into across the full distribution?
lang.rank %>%
  summarise(percentile = mean(pct_non_english <= texas.rank$pct_non_english) * 100)


### -----------------------------------------------------
### 7. Visualization - Highlighting Texas
### -----------------------------------------------------

# Add a flag column to color Texas differently from other states
lang.plot <- lang.rank %>%
  mutate(highlight = ifelse(state == "Texas", "Texas", "Other"))

# Ranked bar chart for all 52 regions (horizontal bars, descending order)
ggplot(lang.plot,
       aes(x = reorder(state, pct_non_english),
           y = pct_non_english,
           fill = highlight)) +
  geom_bar(stat = "identity") +
  coord_flip() +
  scale_fill_manual(values = c("Texas" = "#BF5700", "Other" = "#1B4332")) +
  labs(title = "Non-English Speaking Rate by State (2024 ACS 5-Year Estimates)",
       subtitle = paste0("Texas: Rank ", texas.rank$rank, " (",
                          texas.rank$pct_non_english, "%)"),
       x = "State",
       y = "Non-English Speaking Rate (%)",
       fill = "",
       caption = "Group 10: Seohyun Choi, Zitong Zhu") +
  theme_minimal() +
  theme(axis.text.y = element_text(size = 7),
        legend.position = "none")

ggsave("./output/fig1_all_states_ranked.png", width = 8, height = 11)


# Zoomed-in view of the top 15 regions (for presentation slides)
lang.plot %>%
  filter(rank <= 15) %>%
  ggplot(aes(x = reorder(state, pct_non_english),
             y = pct_non_english,
             fill = highlight)) +
  geom_bar(stat = "identity") +
  geom_text(aes(label = paste0(pct_non_english, "%")),
            hjust = -0.1, size = 3) +
  coord_flip(clip = "off") +
  scale_fill_manual(values = c("Texas" = "#BF5700", "Other" = "#1B4332")) +
  labs(title = "Top 15 States by Non-English Speaking Rate",
       subtitle = paste0("Texas ranks ", texas.rank$rank, " among the top 15"),
       x = NULL,
       y = "Non-English Speaking Rate (%)",
       caption = "Group 10: Seohyun Choi, Zitong Zhu") +
  theme_minimal() +
  theme(legend.position = "none",
        plot.margin = margin(5.5, 40, 5.5, 5.5))

ggsave("./output/fig2_top15_texas_highlight.png", width = 8, height = 6)


### -----------------------------------------------------
### 8. Additional Visualizations
### -----------------------------------------------------

# 8.1 Assign each state to its official US Census Bureau region
# (Northeast / Midwest / South / West). DC is grouped with South,
# per Census Bureau convention. Puerto Rico is a US territory and
# has no official Census region, so it is labeled "Territory" and
# excluded from the boxplot's regional comparison.
region.map <- tibble(
  state = c(
    "Connecticut", "Maine", "Massachusetts", "New Hampshire", "Rhode Island",
    "Vermont", "New Jersey", "New York", "Pennsylvania",
    "Illinois", "Indiana", "Michigan", "Ohio", "Wisconsin", "Iowa", "Kansas",
    "Minnesota", "Missouri", "Nebraska", "North Dakota", "South Dakota",
    "Delaware", "Florida", "Georgia", "Maryland", "North Carolina",
    "South Carolina", "Virginia", "District of Columbia", "West Virginia",
    "Alabama", "Kentucky", "Mississippi", "Tennessee", "Arkansas",
    "Louisiana", "Oklahoma", "Texas",
    "Arizona", "Colorado", "Idaho", "Montana", "Nevada", "New Mexico",
    "Utah", "Wyoming", "Alaska", "California", "Hawaii", "Oregon", "Washington",
    "Puerto Rico"
  ),
  region = c(
    rep("Northeast", 9),
    rep("Midwest", 12),
    rep("South", 17),
    rep("West", 13),
    "Territory"
  )
)

lang.region <- lang.plot %>%
  left_join(region.map, by = "state")

# 8.2 Histogram of all 52 regions, with Texas marked by a dashed line
ggplot(lang.region, aes(x = pct_non_english)) +
  geom_histogram(binwidth = 5, fill = "#1B4332", color = "white", boundary = 0) +
  geom_vline(xintercept = texas.rank$pct_non_english,
             color = "#BF5700", linewidth = 1, linetype = "dashed") +
  annotate("text", x = texas.rank$pct_non_english + 2, y = 10,
           label = paste0("Texas: ", texas.rank$pct_non_english, "%\n(96th percentile)"),
           color = "#BF5700", hjust = 0, fontface = "bold", size = 3.5) +
  labs(title = "Distribution of Non-English Speaking Rate Across 52 Regions",
       subtitle = "Most regions cluster well below Texas's rate",
       x = "Non-English Speaking Rate (%)",
       y = "Number of Regions",
       caption = "Group 10: Seohyun Choi, Zitong Zhu") +
  theme_minimal()

ggsave("./output/fig3_histogram_texas.png", width = 8, height = 5.5)


# 8.3 Boxplot comparing Census regions, with Texas marked as a point
lang.region %>%
  filter(region != "Territory") %>%
  ggplot(aes(x = reorder(region, pct_non_english, median), y = pct_non_english)) +
  geom_boxplot(fill = "#DCE9E2", color = "#1B4332", outlier.shape = NA) +
  geom_jitter(width = 0.12, alpha = 0.4, color = "#1B4332") +
  geom_point(data = lang.region %>% filter(state == "Texas"),
             aes(x = "South", y = pct_non_english),
             color = "#BF5700", size = 4) +
  geom_text(data = lang.region %>% filter(state == "Texas"),
            aes(x = "South", y = pct_non_english, label = "Texas"),
            color = "#BF5700", fontface = "bold", vjust = -1.2, size = 3.5) +
  labs(title = "Non-English Speaking Rate by US Census Region",
       subtitle = "50 states + DC (Puerto Rico excluded; no official Census region)",
       x = "Census Region",
       y = "Non-English Speaking Rate (%)",
       caption = "Group 10: Seohyun Choi, Zitong Zhu") +
  theme_minimal()

ggsave("./output/fig4_boxplot_by_region.png", width = 8, height = 5.5)


# 8.4 Scatter plot: total population vs. non-English speaking rate
ggplot(lang.region, aes(x = total, y = pct_non_english, color = highlight)) +
  geom_point(size = 2.5, alpha = 0.85) +
  ggrepel::geom_text_repel(
    data = lang.region %>% filter(state %in% c("Texas", "California", "Puerto Rico", "New York")),
    aes(label = state), show.legend = FALSE, size = 3.2, color = "black"
  ) +
  scale_x_log10(labels = scales::comma) +
  scale_color_manual(values = c("Texas" = "#BF5700", "Other" = "#1B4332")) +
  labs(title = "Population Size vs. Non-English Speaking Rate",
       subtitle = "Log scale on population; larger states are not automatically higher-rate",
       x = "Total Population Age 5+ (log scale)",
       y = "Non-English Speaking Rate (%)",
       color = "",
       caption = "Group 10: Seohyun Choi, Zitong Zhu") +
  theme_minimal() +
  theme(legend.position = "none")

ggsave("./output/fig5_scatter_population.png", width = 8, height = 5.5)


### -----------------------------------------------------
### 9. Applied Improvement \u2014 One-Sample t-test for Texas
### -----------------------------------------------------

# Idea: is Texas's non-English speaking rate (35.09%) significantly higher
# than what we'd expect from the "typical" region? We treat the other 51
# regions' rates as a sample and test whether their true mean is below
# Texas's specific value.
#
# H0: mean(other 51 regions) = Texas's rate (35.09%)
# H1: mean(other 51 regions) <  Texas's rate (one-sided)
# alpha = 0.05

other.pct <- lang.rank %>%
  filter(state != "Texas") %>%
  pull(pct_non_english)

texas.ttest <- t.test(other.pct,
                       mu = texas.rank$pct_non_english,
                       alternative = "less")

texas.ttest

cat(sprintf(
  "\nOne-sample t-test: t = %.3f, df = %d, p-value = %.2e\nMean of other 51 regions = %.2f%% vs Texas = %.2f%%\n",
  texas.ttest$statistic, texas.ttest$parameter,
  texas.ttest$p.value, mean(other.pct), texas.rank$pct_non_english
))


### -----------------------------------------------------
### 8. Interpretation
### -----------------------------------------------------
#
# - Texas ranks near the top (around #3) out of 52 regions
#   (50 states + DC + Puerto Rico) in non-English speaking rate,
#   well above the overall average.
# - The top-ranked regions are Puerto Rico (an overwhelming #1 due to
#   its Spanish-speaking majority), California, Texas, New Jersey,
#   New Mexico, New York, and Florida -- mostly places with a large
#   Hispanic population share or high levels of border/immigrant inflow.
# - Texas shares a border with Mexico and has a large Spanish-speaking
#   population, which likely explains its high national ranking.
# - By contrast, the lowest-ranked regions (West Virginia, Montana,
#   Mississippi, etc.) tend to be inland/rural states with lower
#   immigrant shares and less population mobility.
#
### =========================================================
