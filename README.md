# Oracle Security Module

This contract is given a `DSValue` as a source to read from. You set a time interval with `changeDelay`. Whenever that `updateDelay` time has passed, it will let you `updateResult`. When you `updateResult` it reads the value from the source and stores it. The previous stored value becomes the current value.

This contracts implements `read` and `getResultWithValidity` from DSValue, but it is not one. It also has a new function `getNextResultWithValidity` to read what the next value will be after a `updateResult`.

```
// create
OSM osm = new OSM(DSValue(src));

// can be updated every hour, on the hour
osm.changeDelay(3600);

(val, ok) = osm.getResultWithValidity() // get current value & its validity
(val, ok) = osm.getNextResultWithValidity() // get upcoming value
val       = osm.read() // get current value, or fail

```

If this `DSValue` has a valid value on creation, the OSM with start with that same value.
