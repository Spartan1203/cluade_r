# R Pocket listener: a tiny HTTP server in base R.
# Runs inside Termux and executes code sent by the R Pocket app.
# Usage: Rscript rserver.R <port> <token>

args <- commandArgs(trailingOnly = TRUE)
port <- as.integer(if (length(args) >= 1) args[1] else 8790)
token <- if (length(args) >= 2) args[2] else ""
if (!nzchar(token)) stop("A token is required")

# Attach the standard packages an interactive R session has (Rscript may skip some)
for (.p in c("methods", "datasets", "utils", "grDevices", "graphics", "stats")) {
  suppressPackageStartupMessages(library(.p, character.only = TRUE))
}
rm(.p)

options(width = 60, warn = 1,
        repos = c(CRAN = "https://cloud.r-project.org"),
        menu.graphics = FALSE, device.ask.default = FALSE)

plot_dir <- file.path(tempdir(), "rpocket_plots")
dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)
.rp <- new.env()
.rp$seq <- 0L
.rp$drawn <- FALSE

# Pick the best PNG device available in this R build
.rp$open_device <- NULL
if (requireNamespace("ragg", quietly = TRUE)) {
  .rp$open_device <- function(f) ragg::agg_png(f, width = 1000, height = 800, res = 144)
} else if (isTRUE(capabilities("cairo"))) {
  .rp$open_device <- function(f) grDevices::png(f, width = 1000, height = 800, res = 144, type = "cairo")
} else if (isTRUE(capabilities("png"))) {
  .rp$open_device <- function(f) grDevices::png(f, width = 1000, height = 800, res = 144)
}

# Note when anything is drawn, so blank pages aren't returned as plots
setHook("before.plot.new", function(...) .rp$drawn <- TRUE)
setHook("before.grid.newpage", function(...) .rp$drawn <- TRUE)

json_str <- function(x) {
  x <- enc2utf8(paste(as.character(x), collapse = "\n"))
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub("\"", "\\\"", x, fixed = TRUE)
  x <- gsub("\n", "\\n", x, fixed = TRUE)
  x <- gsub("\r", "\\r", x, fixed = TRUE)
  x <- gsub("\t", "\\t", x, fixed = TRUE)
  x <- gsub("[\\x01-\\x1f]", "", x, perl = TRUE)
  paste0("\"", x, "\"")
}

call_label <- function(call) {
  if (is.null(call) || (is.call(call) && identical(call[[1]], quote(eval)))) return("")
  paste0(" in ", deparse(call)[1])
}

json_bool <- function(x) if (isTRUE(x)) "true" else "false"

run_code <- function(code) {
  items <- character()
  add <- function(type, text) {
    text <- paste(text, collapse = "\n")
    if (nzchar(text)) {
      items[length(items) + 1L] <<- paste0("{\"t\":", json_str(type), ",\"x\":", json_str(text), "}")
    }
  }

  exprs <- tryCatch(parse(text = code, keep.source = TRUE), error = function(e) e)
  if (inherits(exprs, "error")) {
    add("input", code)
    add("error", paste("Error:", conditionMessage(exprs)))
    return(list(items = items, plots = character()))
  }

  .rp$seq <- .rp$seq + 1L
  prefix <- sprintf("p%05d_", .rp$seq)
  dev_num <- NULL
  .rp$drawn <- FALSE
  if (!is.null(.rp$open_device)) {
    ok <- tryCatch({ .rp$open_device(file.path(plot_dir, paste0(prefix, "%03d.png"))); TRUE },
                   error = function(e) FALSE)
    if (ok) dev_num <- grDevices::dev.cur()
  }

  srcs <- attr(exprs, "srcref")
  for (i in seq_along(exprs)) {
    src <- if (!is.null(srcs)) paste(as.character(srcs[[i]]), collapse = "\n")
           else paste(deparse(exprs[[i]]), collapse = "\n")
    add("input", src)

    tc <- textConnection(NULL, "w")
    emitted <- 0L
    flush_output <- function() {
      vals <- textConnectionValue(tc)
      if (length(vals) > emitted) add("output", vals[(emitted + 1L):length(vals)])
      emitted <<- length(vals)
    }
    sinks <- sink.number()
    sink(tc)
    err <- tryCatch(
      withCallingHandlers({
        res <- withVisible(eval(exprs[[i]], envir = globalenv()))
        if (res$visible) print(res$value)
        NULL
      },
      message = function(m) {
        flush_output()
        add("message", sub("\n$", "", conditionMessage(m)))
        invokeRestart("muffleMessage")
      },
      warning = function(w) {
        flush_output()
        add("warning", paste0("Warning", call_label(conditionCall(w)), ": ", conditionMessage(w)))
        invokeRestart("muffleWarning")
      }),
      error = function(e) e)
    while (sink.number() > sinks) sink()
    if (isIncomplete(tc)) cat("\n", file = tc)
    flush_output()
    close(tc)
    if (inherits(err, "error")) {
      add("error", paste0("Error", call_label(conditionCall(err)), ": ", conditionMessage(err)))
      break
    }
  }

  if (!is.null(dev_num) && dev_num %in% grDevices::dev.list()) {
    try(grDevices::dev.off(dev_num), silent = TRUE)
  }
  plots <- sort(list.files(plot_dir, pattern = paste0("^", prefix, ".*\\.png$")))
  if (!.rp$drawn) {
    unlink(file.path(plot_dir, plots))
    plots <- character()
  }
  plots <- plots[file.info(file.path(plot_dir, plots))$size > 0]
  list(items = items, plots = plots)
}

read_request <- function(con) {
  buf <- raw(0)
  end <- as.raw(c(13, 10, 13, 10))
  repeat {
    b <- readBin(con, "raw", 1L)
    if (!length(b)) return(NULL)
    buf <- c(buf, b)
    n <- length(buf)
    if (n >= 4 && identical(buf[(n - 3):n], end)) break
    if (n > 65536) return(NULL)
  }
  lines <- strsplit(rawToChar(buf), "\r\n", fixed = TRUE)[[1]]
  first <- strsplit(lines[1], " ", fixed = TRUE)[[1]]
  headers <- list()
  for (l in lines[-1]) {
    p <- regexpr(":", l, fixed = TRUE)
    if (p > 0) headers[[tolower(substr(l, 1, p - 1))]] <- trimws(substring(l, p + 1))
  }
  len <- suppressWarnings(as.integer(headers[["content-length"]]))
  if (!length(len) || is.na(len)) len <- 0L
  body <- ""
  if (len > 0) {
    r <- raw(0)
    while (length(r) < len) {
      chunk <- readBin(con, "raw", len - length(r))
      if (!length(chunk)) break
      r <- c(r, chunk)
    }
    body <- rawToChar(r)
    Encoding(body) <- "UTF-8"
  }
  list(method = first[1], path = first[2], headers = headers, body = body)
}

respond <- function(con, status, body, type = "application/json; charset=utf-8") {
  if (is.character(body)) body <- charToRaw(enc2utf8(body))
  head <- paste0("HTTP/1.1 ", status, "\r\nContent-Type: ", type,
                 "\r\nContent-Length: ", length(body),
                 "\r\nConnection: close\r\n\r\n")
  writeBin(c(charToRaw(head), body), con)
  flush(con)
}

handle <- function(con) {
  req <- read_request(con)
  if (is.null(req)) return(invisible())
  if (!identical(req$headers[["x-token"]], token)) {
    return(respond(con, "401 Unauthorized", "{\"error\":\"bad token\"}"))
  }
  path <- sub("\\?.*$", "", req$path)

  if (path == "/ping") {
    respond(con, "200 OK", paste0(
      "{\"ok\":true,\"r\":", json_str(paste(R.version$major, R.version$minor, sep = ".")),
      ",\"plots\":", json_bool(!is.null(.rp$open_device)),
      ",\"wd\":", json_str(getwd()), "}"))
  } else if (path == "/eval" && req$method == "POST") {
    res <- run_code(req$body)
    respond(con, "200 OK", paste0(
      "{\"items\":[", paste(res$items, collapse = ","), "],",
      "\"plots\":[", paste(vapply(res$plots, json_str, ""), collapse = ","), "]}"))
  } else if (grepl("^/plot/p[0-9]+_[0-9]+\\.png$", path)) {
    f <- file.path(plot_dir, basename(path))
    if (file.exists(f)) {
      respond(con, "200 OK", readBin(f, "raw", file.info(f)$size), "image/png")
    } else {
      respond(con, "404 Not Found", "{\"error\":\"no such plot\"}")
    }
  } else if (path == "/files") {
    f <- list.files(getwd(), all.files = FALSE, no.. = TRUE)
    info <- file.info(file.path(getwd(), f))
    entries <- vapply(seq_along(f), function(i) paste0(
      "{\"n\":", json_str(f[i]), ",\"d\":", json_bool(info$isdir[i]),
      ",\"s\":", if (is.na(info$size[i])) 0 else format(info$size[i], scientific = FALSE), "}"), "")
    respond(con, "200 OK", paste0("{\"wd\":", json_str(getwd()), ",\"files\":[",
                                  paste(entries, collapse = ","), "]}"))
  } else {
    respond(con, "404 Not Found", "{\"error\":\"unknown path\"}")
  }
}

srv <- serverSocket(port)
cat("R Pocket listener on port", port, "\n")
repeat {
  con <- tryCatch(socketAccept(srv, blocking = TRUE, open = "r+b", timeout = 86400),
                  error = function(e) NULL)
  if (is.null(con)) next
  tryCatch(handle(con), error = function(e) {
    try(respond(con, "500 Internal Server Error",
                paste0("{\"error\":", json_str(conditionMessage(e)), "}")), silent = TRUE)
  })
  try(close(con), silent = TRUE)
}
