package powerPing

@GrabResolver(name='artifactory', root='http://artifact.praqma.net:/artifactory/repo/', m2Compatible=true)
@Grab(group = 'org.yaml', module = 'snakeyaml', version = '1.5')
import org.yaml.snakeyaml.Yaml
@Grab('com.github.kevinsawicki:http-request:3.1')
import com.github.kevinsawicki.http.*

class powerPing extends Script {

    final Yaml YAML = new Yaml()

    @Override
    Object run() {
        // Check for correct script parameters
        if (!args) {
            println "ERROR: Missing script parameters."
            println "powerPing [config file] [environments...]"
            System.exit(1)
        }

        // Load configuration and default ports
        def configFile = new File(args[0])
        if (!configFile.exists()) {
            println "ERROR: Could not find configuration file ${args[0]}"
			System.exit(1)
        }
        def configuration = YAML.load(configFile.text)
        def defaultsMap = loadDefaults(configuration)

        // Loop through passed in environments and curl their addresses:ports
        def failure = false
        def environmentNames = args[1..-1]
        for(def environmentName : environmentNames){
            if(environmentName.equalsIgnoreCase("configuration")){
                println "ERROR: $environmentName is a reserved keyword. It cannot be tested as an environment!"
                failure = true
                continue
            }

            def environment = configuration[environmentName]
            if (!environment) {
                println "ERROR: Environment $environmentName not found in configuration file!"
                failure = true
                continue
            }

            println "***** TESTING: $environmentName"
            for(def address : environment) {
                def addressName = address.key
                def ports = address.value.ports
                def paths = address.value.paths

                println ""
                println "$addressName $ports"
                println "-----"
                if (!doDnsLookup(addressName)) {
					println "ERROR: $configFile in DNS lookup: could not lookup $addressName"
                    failure = true
                    println "----------"
                    continue
                }

                def expandedPorts = []
                def expSuccess = fillWithExpandedPorts(expandedPorts, ports, defaultsMap)
                if (!expSuccess){
                    failure = true
                } else {
                    for(def port : expandedPorts) {
                        if (!doPortCheck(addressName, port)) {
						    println "ERROR: $configFile in port check: could not connect to $addressName on port $port"
                            failure = true
                        }
                    }
                }

                for(def path : paths) {
                    if (!doCurl(path)) {
						println "ERROR: $configFile in curl check: could not access URL $path"
                        failure = true
                    }
                }

                println "----------"
            }
        }
        if (failure)
            System.exit(1)
    }

    /**
     * Fills a list with all the given ports, replacing strings with ports from the defaults map
     * @param expandedPorts the List to fill
     * @param portValues the port values to expand
     * @param defaultsMap the default ports map
     * @return true if successful, false if expansion failed
     */
    boolean fillWithExpandedPorts(def expandedPorts, def portValues, def defaultsMap) {
        for(def portValue : portValues){
            if (portValue.toString().isNumber()) {
                expandedPorts.add(portValue)
            } else {
                def defaultPorts = defaultsMap[portValue]
                if (defaultPorts)
                    expandedPorts.addAll(defaultPorts)
                else {
                    println("ERROR: Failed to expand port value $portValue.")
                    return false
                }
            }
        }
        return true
    }

    /**
     * Fills a map with all the ports defined in the config's 'defaults' section.
     * @param yamlMap the loaded YAML map
     * @return a Map<String, Int[]> with all the default ports
     */
    private Map loadDefaults(yamlMap) {
        def defaultMap = [:]
        if (yamlMap['configuration']) {
            yamlMap['configuration'].each {
                defaultMap.put(it.key, it.value)
            }
        }
        return defaultMap
    }

    boolean doCurl(String url) {
        print "curl $url: "
        try {
            def req = HttpRequest.get(url)
            req.trustAllCerts()
            req.trustAllHosts()
            def response = req.code()
            println "ok (response: $response)"
            return true
        } catch (Exception ex) { // FIXME - could we catch some specific exception, to catch timeout? to catch unkonw host? unknow url and print out that error together with stack trace? then for the rest, just catch them by your generic ERROR
            print "ERROR "
            println "(" + ex + ")"
            return false
        }
    }

    private boolean doDnsLookup(String address) {
        print "dns: "
        try {
            def inetAddress = InetAddress.getByName(address)
            println "ok (found: $inetAddress.hostAddress)"
            return true
        } catch (Exception ex) {
            print "ERROR "
            println "(" + ex + ")"
            return false
        }
    }

    private boolean doPortCheck(String address, int port) {
        print "port $port: "
        try {
            new Socket().connect(new InetSocketAddress(address, port), 2000);
            println "ok"
            return true
        } catch (Exception ex) {
            print "ERROR "
            println "(" + ex + ")"
            return false
        }

    }
}
