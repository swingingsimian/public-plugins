window.rate_limiter = (nochange_ms,lastreq_ms) ->
  timer = null
  last_request = null
  pending = null

  return (data) ->
    d = $.Deferred()
    # cancel any outstanding reuqests
    if pending
      pending.reject()
      clearTimeout(timer)
      pending = null
    # have we waited long enough, anyway?
    now = new Date().getTime()
    if (not last_request) or now - last_request > lastreq_ms
      last_request = now 
      d.resolve(data)
    else
      pending = d
      last_request = now
      timer = setTimeout((() -> d.resolve(data)),nochange_ms)
    return d

window.then_loop = (fn) ->
  step = (v) ->
    d = fn(v)
    if d and $.isFunction(d.promise)
      return d.then(step)
    else
      return d
  return step

in_endless_chunks = (chunksize,fn) ->
  chunk_loop = then_loop ([got,halt]) =>
    if halt then return got
    return fn(got,chunksize).then (len) =>
      if len == -1 then return [got,1] else return [got+len,0]
  return $.Deferred().resolve([0,0]).then(chunk_loop)

window.in_chunks = (total,maxchunksize,fn) ->
  if total == -1 then return in_endless_chunks(maxchunksize,fn)
  chunk_loop = then_loop (got) =>
    if total - got <= 0 then return got
    chunksize = total - got
    if chunksize > maxchunksize then chunksize = maxchunksize
    return fn(got,chunksize).then (len) =>
      return got + len
  return $.Deferred().resolve(0).then(chunk_loop)

window.solr_current_species = () ->
  url = window.location.href
  parts = url.split('/')
  # 0 = http: ; 1 = '' ; 2 = hostpart ; 3... first url part
  path = parts[3].toLowerCase()
  latin = $.solr_config('spnames.%',path)
  if !latin then latin = path
  species = latin.toLowerCase()
  if !$.solr_config('revspnames.%',species) then return null
  return species

