package XmlAccess

class Command {
    static def run(String command) {
        return run(command, new File(System.properties.'user.dir'))
    }

    static def run(String command, File workingDir) {
        println command
        def process = new ProcessBuilder(command)
                .directory(workingDir)
                .redirectErrorStream(true)
                .start()
        process.inputStream.eachLine { println it }
        process.waitFor();
        return process.exitValue()
    }
}
