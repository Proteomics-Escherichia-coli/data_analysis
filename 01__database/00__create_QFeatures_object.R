#' 2022-10-15 Read the evidence file and organize the data.
#' I'm using the QFeatures object to aggregate at peptides and protein levels
#' using the `colMedians()` function from {MatrixGenerics}
suppressMessages(library(QFeatures))

path_data <- "./01__database/"

# Import the raw data (evidence) ------------------------------------------

data_raw <- read.delim(file.path(path_data, "raw_data/evidence.txt"))

cols <- list(
  charge = "Charge",
  sequence = 'Sequence',
  modified_sequence = 'Modified.sequence',
  modifications = 'Modifications',
  protein_group = 'Proteins',
  protein = 'Leading.Razor.Protein',
  experiment = 'Experiment',
  reverse = 'Reverse',
  contaminant = 'Contaminant',
  intensity = 'Intensity'
)
data_raw <- data_raw[, as.character(cols)]
colnames(data_raw) <- names(cols)
head(data_raw)


# Filters out contaminants and reverse sequences --------------------------
data_raw <- data_raw[
  which(data_raw$contaminant != '+' & data_raw$reverse != '+'),]

# Removing Tetracycline group ---------------------------------------------
unique(data_raw$experiment)
data_raw <- data_raw[!(data_raw$experiment %in% c("Tet2", "Tet3", "Tet4")), ]
dim(data_raw)

# Creating a unique id, since there are multiple peptides corresponding to the
# same sequence
chosen_cols <- c("modified_sequence", "protein", "experiment", "intensity")
data_raw <- data_raw[, chosen_cols] |> 
  dplyr::group_by(experiment, modified_sequence, protein) |> 
  dplyr::mutate(number_peptides = dplyr::n()) |> 
  dplyr::ungroup() |>
  dplyr::arrange(experiment, modified_sequence, protein)
data_raw$unique_id <- seq.int(1, nrow(data_raw))
head(data_raw)
dim(data_raw)

# Pivot to create the data matrix at PSMs level ---------------------------
pivotted_psms <- tidyr::pivot_wider(
  data = data_raw,
  id_cols = c(unique_id, number_peptides, modified_sequence, protein),
  names_from = experiment,
  values_from = intensity)

# Columns data referring the design of experiment -------------------------
samples_names <- colnames(pivotted_psms)[-c(1:4)]
map_names <- list(
  "amp" = "Ampicillin",
  "cef" = "Cefotaxime",
  "imp" = "Imipenem",
  "cip" = "Ciprofloxacin",
  "cont" = "Control"
  # "tet" = "Tetracycline"
)
group_names <- as.character(map_names[
  tolower(gsub("[0-9]+", "", samples_names))])
col_data <- DataFrame(group = group_names,
                      replicate = rep(1L:3L, length(map_names)),
                      sample_names = samples_names,
                      row.names = paste0("Sample_",
                                         seq_len(length(group_names))))

# Creating a SummarizedExperiment for PSMs level --------------------------
row_data <- pivotted_psms[, c(1:4)]
m_psms <- as.matrix(pivotted_psms[, -c(1:4)])
colnames(m_psms) <- rownames(col_data)
se_psms <- SummarizedExperiment(assays = list(intensity = m_psms),
                                rowData = row_data, colData = col_data)

# Creating the QFeature object --------------------------------------------
# fts <- QFeatures(list(psms = se_psms), colData = col_data)
colnames(pivotted_psms)[5:19] <- rownames(col_data)
fts <- readQFeatures(table = pivotted_psms, ecol = 5:19, name = "psms")
colData(fts) <- col_data

# Aggregate data at peptide level -----------------------------------------
# rows: peptides sequences and columns: samples
fts <- aggregateFeatures(object = fts, i = "psms", fcol = "modified_sequence",
                         name = "peptides", fun = colMedians, na.rm = TRUE)
head(assay(fts[[2L]], 2))
rowData(fts[[2L]])

# The same as:
# pivotted__peptides <- tidyr::pivot_wider(
#   data = data_raw,
#   id_cols = c(modified_sequence, protein),
#   names_from = experiment,
#   values_from = intensity,
#   values_fn = sum)

# Save the data -----------------------------------------------------------
saveRDS(object = fts,
        file = file.path(path_data, "processed_data", "QFeature_obj.rds"))
