package transformAndRun

@GrabResolver(name='artifactory', root='http://artifactory.yourcompany.com/artifactory/repo/', m2Compatible=true)
@Grab(group = 'org.yaml', module = 'snakeyaml', version = '1.5')
import org.yaml.snakeyaml.Yaml
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import groovy.text.SimpleTemplateEngine

class transformAndRun extends Script {

    final Yaml YAML = new Yaml()

    @Override
    Object run() {
        if (!args) {
            println "Missing YAML configuration file argument"
            System.exit(1)
        }
        def configFile = new File(args[0])
        def config = YAML.load(configFile.text)

        def commands = config.commands.collect { new Command(it) }
        if (commandsAreMissingVariables(commands) || filesAreMissingVariables(config.files))
            System.exit(1)

        // Expand commands with environment variables
        commands.each { it.expanded = expandWithEnvironment(it.unexpanded) }

        // We ALWAYS want to clean up any expanded files to protect our secrets. Hence the giant try/finally
        try {
            def processFailure = false
            // Expand files..
            config.files.each { filePair ->
                def targetFile = new File(filePair[0])
                def transformFile = new File(filePair[1])

                // Backup before expansion
                def originalPath = targetFile.toPath()
                def backupPath = new File(targetFile.path + ".bak").toPath()
                Files.copy(originalPath, backupPath, StandardCopyOption.REPLACE_EXISTING)

                // Expand with environment variables
                def expandedContents = expandWithEnvironment(targetFile.text)

                // Expand with transform maps
                def transformBinding = YAML.load(transformFile.text)
                def transformEngine = new SimpleTemplateEngine()
                try {
                    expandedContents = transformEngine.createTemplate(expandedContents).make(transformBinding).toString()
                } catch (MissingPropertyException ex) {
                    processFailure = true
                    def matcher = (ex.message =~ /No such property: ([\w_-]+) .*/)
                    // Will always match, but we can't access the groups without calling matches() first.
                    if (matcher.matches()) {
                        def variable = matcher.group(1)
                        println "ERROR: Variable $variable not found in [$targetFile, $transformFile]. Are you missing environment variables?"
                        return
                    } else {
                        println ex.message
                        return;
                    }
                }

                // Overwrite original contents with transformed contents
                Files.write(targetFile.toPath(), expandedContents.bytes)
            }

            if (!processFailure) {
                // Run commands..
                for (def command : commands) {
                    def exitValue = command.run()
                    println "Exit value " << exitValue << " for command {" << command.unexpanded << "}"
                    if (exitValue != 0) {
                        println "Command failed. Stopping command executions."
                        processFailure = true;
                        break;
                    }
                }
            }
        } finally {
            //Restore backups
            try {
                config.files.each { filePair ->
                    def targetFile = new File(filePair[0])
                    Files.move(new File(targetFile.path + ".bak").toPath(), targetFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
                }
            } catch (Exception e) {
                println "ERROR: Error during cleanup. Expanded files may have survived!!"
            } finally {
                System.exit(processFailure ? 1 : 0)
            }
        }
    }

    boolean commandsAreMissingVariables(List<Command> commands) {
        def commandVariables = commands.collect { command -> getVariables(command.unexpanded) }.flatten()
        def missingVariables = false
        commandVariables.each {
            if (!it.expandWithEnvironment()) {
                missingVariables = true
                println "ERROR: Variable $it.key not found for command {$it.source}. Are you missing environment variables?"
            }
        }
        return missingVariables
    }

    boolean filesAreMissingVariables(List<Map<String, String>> filePairs) {
        def variableMismatch = false
        filePairs.each { filePair ->
            def targetFile = new File(filePair[0])
            def transformFile = new File(filePair[1])
            def targetVariables = getVariables(targetFile)
            def transformVariables = YAML.load(transformFile.text).collect {
                new Variable(source: filePair[1], key: it.key, value: it.value)
            }

            targetVariables.each { targetVar ->
                if (!transformVariables.any { it.key.equals(targetVar.key) } && !targetVar.expandWithEnvironment()) {
                    variableMismatch = true
                    println "ERROR: Variable $targetVar.key not found in [$targetVar.source, $transformFile]. Are you missing environment variables?"
                }
            }
            transformVariables.each { transformVar ->
                if (!targetVariables.any { it.key.equals(transformVar.key) }) {
                    variableMismatch = true
                    println "ERROR: Variable $transformVar.key not used in [$targetFile, $transformVar.source]. Are you using the wrong transform file?"
                }
            }
        }
        return variableMismatch
    }

    /**
     * Expands parameters in a text with environment variables where possible
     * @param text the text you want to expand
     * @return the expanded text
     */
    String expandWithEnvironment(String text) {
        def variables = getVariables(text)
        variables.each { var ->
            if (var.expandWithEnvironment())
                text = text.replace(var.prependedKey, var.value)
        }
        return text
    }

    /**
     * Gets all variables in the given text
     * eg. ['$user'] in '$user wants to dance.')
     * @param text the text to get all variables from
     * @return a list of all variables
     */
    List<Variable> getVariables(String text) {
        def keyPattern = /\$[\w_-]+/;
        text.findAll(keyPattern).collect {
            new Variable(source: text, key: it.substring(1))
        }
    }

    /**
     * Gets all variables in the given file
     * eg. ['$user'] in '$user wants to dance.')
     * @param text the text to get all variables from
     * @return a list of all variables
     */
    List<Variable> getVariables(File file) {
        def keyPattern = /\$[\w_-]+/;
        file.text.findAll(keyPattern).collect {
            new Variable(source: file, key: it.substring(1))
        }
    }

    /**
     * Class to facilitate working with variables in the script.
     */
    class Variable {
        String source   //File or command
        String key      //Without $
        String value

        String getPrependedKey() {
            return '$' + key
        }

        boolean expandWithEnvironment() {
            value = Environment.instance.getEnv(key)
            return value ? true : false
        }
    }

    /**
     * Class to facilitate working with commands
     */
    class Command {
        String unexpanded
        String expanded

        public Command(String unexpanded) {
            this.unexpanded = unexpanded
        }

        /**
         * Runs a command, prints its output and returns exit value
         * @param command the command to run
         * @return the exit value of the command
         */
        int run() {
            def commandToRun = isOsWindows() ? "cmd /c " + expanded : expanded
            Process process = Runtime.getRuntime().exec(commandToRun, System.getenv().toString())
            process.inputStream.eachLine { println it }
            return process.waitFor();
        }

        private boolean isOsWindows() {
            def os = System.getProperty('os.name').toUpperCase()
            return os.contains("WINDOWS")
        }
    }

    /**
     * Makes it possible to add environment variables in tests
     */
    @Singleton
    public class Environment {
        def Map<String, String> variables = new HashMap<>();

        String getEnv(String key) {
            String value = variables.get(key)
            return value ? value : System.getenv(key)
        }
    }
}
