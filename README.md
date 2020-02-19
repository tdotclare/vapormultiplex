# vapormultiplex
A Naive Multiplexed/Multihomed Extension for Vapor Application

Based heavily on native Vapor4-beta Application.Server and ServeCommand as of 2/18/20.

--DURING CONFIGURATION--
```config(app)```

```
 a.commands.use(MultiplexServeCommand(), as: "multiserve")

for i in 0..<8 {
  a.server.configuration.port = 8080+i  // Assumes prior set base configuration
  a.servers.configs.append(a.server.configuration)
}
```

--RUN BUILT APP--
```vapor Run multiserve```

Result - 8 identical HTTPServer responders listening on ports 8080-8087, utilizing the same configured routing tree/middleware.
Servers could utilize any variety of different configurations, however - eg:
* HTTP & HTTPS handlers on two servers
* Multiple HTTPS handlers with different TLSConfig certificates for multiple domains
* Split external and internal handlers on public & private interfaces for endpoint jailing
