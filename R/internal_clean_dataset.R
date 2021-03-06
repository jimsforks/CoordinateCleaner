# 1. The autocorrelation function returning a gamma vector, paramters =
# nbins and roudning, the latter = 0 for now
#' @importFrom graphics hist plot abline segments
#' @importFrom stats cov quantile aggregate
.CalcACT <- function(data, 
                     digit_round = 0, 
                     nc = 3000, 
                     graphs = TRUE, 
                     graph_title = "Title",
                     rarefy = FALSE) {
  if (rarefy) {
    data <- unique(data)
  }

  data_units <- sort(abs(data))

  if (digit_round > 0) {
    # if set to 10 takes only units into account
    data_units <- data_units - 
      round(floor(data_units / digit_round) * digit_round)
  }

  if (graphs) {
    h <- graphics::hist(data_units, nclass = nc, main = graph_title)
  } else {
    h <- graphics::hist(data_units, nclass = nc, plot = FALSE)
  }

  f <- h$counts
  max_range <- round(length(f) * 0.9)
  gamma_0 <- stats::cov(f[1:max_range], f[1:max_range])

  gamma_vec <- c()

  for (k in 1:max_range) {
    f_0 <- f[-(1:k)]
    f_k <- f[-((length(f) - k + 1):(length(f)))]
    gamma_vec <- c(gamma_vec, stats::cov(f_0, f_k) / gamma_0)
  }

  # add coordinates
  coords <- h$mids[1:max_range]

  # plot outlier bins vs coordinates
  if (graphs) {
    plot(coords, gamma_vec)
  }

  # create output data.frame, with the gamma vector and the respective
  # coordinates

  out <- data.frame(gamma = gamma_vec, coords = coords)

  return(out)
}

# 2.function to run a sliding window over the gamma vector, identifying
# outliers, using the interquantile range. Two parameters: window size
# (fixed at 10 points for now) and the outlier threshold (T1, this is the
# most important paramter for the function). The function returns the number
# of non-consecutive 1 (= outlier found)
.OutDetect <- function(x, T1 = 7, 
                       window_size = 10, 
                       detection_rounding = 2,
                       detection_threshold = 6, 
                       graphs = TRUE) {
  
  # The maximum range end for the sliding window
  max_range <- nrow(x) - window_size 

  out <- matrix(ncol = 2)

  for (k in 1:max_range) {
    # sliding window
    sub <- x[k:(k + window_size), ] # sliding window

    # interquantile range outlier detection
    quo <- stats::quantile(sub$gamma, c(0.25, 0.75), na.rm = TRUE)
    outl <- matrix(nrow = nrow(sub), ncol = 2)
    outl[, 1] <- sub$gamma > (quo[2] + stats::IQR(sub$gamma) * T1) 
    outl[, 2] <- sub$coord
    out <- rbind(out, outl)
  }

  out <- stats::aggregate(out[, 1] ~ out[, 2], FUN = "sum")
  names(out) <- c("V1", "V2")
  out <- out[, c(2, 1)]
  # only 'outliers' that have at least been found by at least 6 sliding windows
  out[, 1] <- as.numeric(out[, 1] >= detection_threshold) 

  # A distance matrix between the outliers we use euclidean space, because 1)
  # we are interest in regularity, not so much the absolute distance, 2) grids
  # might often be in lat/lon and 3) most grids wil only spann small spatial
  # extent
  outl <- out[out[, 1] == 1, ]

  if (nrow(outl) == 0) {
    out <- data.frame(n.outliers = 0, 
                      n.regular.outliers = 0, 
                      regular.distance = NA)
  } else if (nrow(outl) == 1) {
    if (graphs) {
      graphics::abline(v = outl[, 2], col = "green")
    }

    out <- data.frame(n.outliers = 1, 
                      n.regular.outliers = 0, 
                      regular.distance = NA)
  } else {
    # add the identified outliers to the plot
    if (graphs) {
      graphics::abline(v = outl[, 2], col = "green")
    }

    # calculate the distance between outliers
    dist_m <- round(stats::dist(round(outl[, 2, drop = FALSE], 
                                      detection_rounding),
                                diag = FALSE), 
                    detection_rounding)
    dist_m[dist_m > 2] <- NA

    if (length(dist_m) == sum(is.na(dist_m))) {
      out <- data.frame(
        n.outliers = nrow(outl), n.regular.outliers = 0,
        regular.distance = NA
      )
    } else {
      # process distance matrix
      dist_m[dist_m < 10^(-detection_rounding)] <- NA
      dists <- c(dist_m)
      dists <- sort(table(dists))
      dist_m <- as.matrix(dist_m)
      dist_m[row(dist_m) <= col(dist_m)] <- NA

      # select those with the most common distance
      # find the most common distance between points
      com_dist <- as.numeric(names(which(dists == max(dists)))) 

      # if there is more than one probably no bias
      sel <- which(dist_m %in% com_dist[1])
      # identify rows with at least one time the most common distance
      sel <- unique(arrayInd(sel, dim(dist_m))) 

      # sel <- unique(as.numeric(colnames(dist_m)[sel[,1]]))

      reg_outl <- cbind(outl[sel[, 1], 2], outl[sel[, 2], 2])

      if (graphs) {
        # find the right y to plot the segments
        y0 <- max(x$gamma)

        if (y0 < 0.3 | y0 > 2) {
          y1 <- max(x$gamma) - max(x$gamma) / nrow(reg_outl)
        } else {
          y1 <- max(x$gamma) - 0.1
        }
        ys <- seq(y0, y1, by = -((y0 - y1) / (nrow(reg_outl) - 1)))

        segments(
          x0 = reg_outl[, 1], x1 = reg_outl[, 2], y0 = ys, y1 = ys,
          col = "red"
        )
      }
      # output: number of outliers, number of outliers with the most common
      # distance, the most common distance
      out <- data.frame(
        n.outliers = nrow(outl), n.regular.outliers = nrow(reg_outl),
        regular.distance = com_dist[1]
      )
    }
  }
  return(out)
}
