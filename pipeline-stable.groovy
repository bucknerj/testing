// Resource limits — morrison has 16 cores; reserve 4 for desktop use
def MAX_BUILD_CONCURRENT = 2   // concurrent ninja builds
def BUILD_THREADS = 6          // -j per build (2 × 6 = 12 cores)
def MAX_TEST_CONCURRENT = 4    // concurrent test runs

// Run a map of closures in batches of the given size
def runInBatches(Map jobs, int batchSize) {
    def jobList = jobs.collect { k, v -> [k, v] }
    for (int i = 0; i < jobList.size(); i += batchSize) {
        def batch = [:]
        def end = Math.min(i + batchSize, jobList.size())
        for (int j = i; j < end; j++) {
            batch[jobList[j][0]] = jobList[j][1]
        }
        parallel batch
    }
}

def ENV_SETUP = '''
    eval "$(/home/bucknerj/.local/bin/micromamba shell hook --shell zsh)"
    micromamba activate workshop
    export FFTW_HOME=$CONDA_PREFIX
'''

// Shell snippet to rotate test output: saves current output as old/
def TEST_ROTATE = '''
    if [[ -d output ]]; then
        rm -rf old
        mkdir old
        cp -r output* old/
        rm -rf output*
    fi
    if [[ -d old ]]; then
        for f in test.log compare.log diff.log test_results.xml; do
            if [[ -f $f ]]; then cp $f old/; rm $f; fi
        done
    fi
'''

pipeline {
    agent any
    options {
        timeout(time: 6, unit: 'HOURS')
        timestamps()
    }
    stages {
        stage('Checkout') {
            steps {
                git branch: 'stable-release', url: 'gitlab:/bucknerj/dev-release'
            }
        }
        stage('Checkout Testing') {
            steps {
                dir('testing') {
                    git branch: 'main',
                        url: 'git@github-bucknerj:bucknerj/testing.git'
                }
            }
        }
        stage('Load Configs') {
            steps {
                script {
                    def json = sh(script: """
                        ${ENV_SETUP}
                        python \${WORKSPACE}/testing/charmm-test list --json
                    """, returnStdout: true).trim()
                    def parsed = new groovy.json.JsonSlurper().parseText(json)
                    // Convert LazyMap to HashMap for Jenkins CPS serialization
                    charmmConfigs = new HashMap(parsed)
                    charmmConfigs.each { k, v -> charmmConfigs[k] = new HashMap(v) }
                    echo "Loaded ${charmmConfigs.size()} configurations: ${charmmConfigs.keySet().sort().join(', ')}"
                }
            }
        }
        stage("Configure") {
            steps {
                script {
                    def parallelJobs = [:]
                    charmmConfigs.each { name, cfg ->
                        parallelJobs["Configure ${name}"] = {
                            stage("Configure ${name}") {
                                echo "Configuring ${name}..."
                                sh """
                                    ${ENV_SETUP}
                                    if [[ ! -d install-${name} ]]; then
                                        tool/NewCharmmTree install-${name}
                                    fi
                                    pushd install-${name}
                                    rm -rf build/cmake
                                    ./configure --with-ninja ${cfg.configure}
                                    popd
                                """
                                echo "...finished configuring ${name}"
                            }
                        }
                    }
                    parallel parallelJobs
                }
            }
        }
        stage("Build") {
            steps {
                script {
                    def buildJobs = [:]
                    charmmConfigs.each { name, cfg ->
                        buildJobs["Build ${name}"] = {
                            stage("Build ${name}") {
                                echo "Building ${name}..."
                                sh """
                                    ${ENV_SETUP}
                                    pushd install-${name}
                                    nice -n 10 ninja -j ${BUILD_THREADS} -C build/cmake install
                                    popd
                                """
                                echo "...finished building ${name}"
                            }
                        }
                    }
                    runInBatches(buildJobs, MAX_BUILD_CONCURRENT)
                }
            }
        }
        stage("Test") {
            steps {
                script {
                    // GPU tests — run sequentially to avoid GPU memory contention
                    charmmConfigs.findAll { name, cfg ->
                        cfg.test != false && cfg.gpus
                    }.each { name, cfg ->
                        stage("Test ${name} (GPU)") {
                            echo "Testing ${name} (GPU)..."
                            sh """
                                ${ENV_SETUP}
                                export CUDA_VISIBLE_DEVICES=0
                                pushd install-${name}/test
                                ${TEST_ROTATE}
                                nice -n 10 ./test.com ${cfg.test_args} output old/output &> test.log
                                popd
                            """
                            echo "...finished testing ${name}"
                        }
                    }

                    // CPU tests — run in batches
                    def cpuTestJobs = [:]
                    charmmConfigs.findAll { name, cfg ->
                        cfg.test != false && cfg.test_args && !cfg.gpus
                    }.each { name, cfg ->
                        cpuTestJobs["Test ${name}"] = {
                            stage("Test ${name}") {
                                echo "Testing ${name}..."
                                sh """
                                    ${ENV_SETUP}
                                    pushd install-${name}/test
                                    ${TEST_ROTATE}
                                    nice -n 10 ./test.com ${cfg.test_args} output old/output &> test.log
                                    popd
                                """
                                echo "...finished testing ${name}"
                            }
                        }
                    }
                    runInBatches(cpuTestJobs, MAX_TEST_CONCURRENT)
                }
            }
        }
        stage("Pytest pyCHARMM") {
            steps {
                script {
                    charmmConfigs.findAll { name, cfg -> cfg.pytest }.each { name, cfg ->
                        echo "Running pyCHARMM pytest suite against install-${name}..."
                        def rc = sh(returnStatus: true, script: """
                            ${ENV_SETUP}
                            pushd install-${name}
                            export CHARMM_DATA_DIR=\$(pwd)/toppar
                            cd tool/pycharmm
                            set +e
                            nice -n 10 pytest -v --tb=short --junitxml=pytest-results.xml tests/ 2>&1 | tee pytest.log
                            pytest_rc=\${PIPESTATUS[0]}
                            echo ""
                            echo "pytest exit code: \$pytest_rc"
                            ls -la pytest-results.xml 2>/dev/null || echo "WARNING: pytest-results.xml was not written (pytest likely crashed)"
                            popd
                            exit \$pytest_rc
                        """)
                        echo "pytest returned ${rc}"
                        if (fileExists("install-${name}/tool/pycharmm/pytest-results.xml")) {
                            junit "install-${name}/tool/pycharmm/pytest-results.xml"
                        } else {
                            unstable("pytest for ${name} did not produce pytest-results.xml")
                        }
                        echo "...finished pyCHARMM pytest (${name})"
                    }
                }
            }
        }
        stage("Report") {
            steps {
                script {
                    def testableNames = charmmConfigs.findAll { name, cfg ->
                        cfg.test != false && cfg.test_args
                    }.keySet().join(' ')
                    echo "Grading test results..."
                    sh """
                        ${ENV_SETUP}
                        export CHARMM_TEST_HOME=\${WORKSPACE}
                        python \${WORKSPACE}/testing/charmm-test grade \
                            --tol 0.0001 --xml test-results.xml \
                            ${testableNames}
                    """
                    junit 'test-results.xml'
                    echo "...finished grading"
                }
            }
        }
    }
    post {
        always {
            archiveArtifacts artifacts: 'install-*/test/*.log,install-*/test/*.xml,install-*/tool/pycharmm/pytest*',
                             allowEmptyArchive: true
        }
        failure {
            echo 'Pipeline failed — check archived test logs for details'
        }
    }
}
