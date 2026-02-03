name := "financial-transaction-processor"

version := "1.0"

scalaVersion := "2.12.17"

// Dependências Spark e AWS
libraryDependencies ++= Seq(
  // Spark Core (fornecido pelo runtime do Glue)
  "org.apache.spark" %% "spark-core" % "3.3.0" % "provided",
  "org.apache.spark" %% "spark-sql" % "3.3.0" % "provided",

  // AWS SDK para DynamoDB
  "com.amazonaws" % "aws-java-sdk-dynamodb" % "1.12.529",

  // AWS SDK para OpenSearch
  "org.opensearch.client" % "opensearch-rest-client" % "2.11.0",
  "org.opensearch.client" % "opensearch-rest-high-level-client" % "2.11.0",

  // Processamento JSON
  "com.fasterxml.jackson.core" % "jackson-databind" % "2.15.2",
  "com.fasterxml.jackson.module" %% "jackson-module-scala" % "2.15.2",

  // Logging
  "org.slf4j" % "slf4j-api" % "1.7.36" % "provided",

  // Testes (opcional)
  "org.scalatest" %% "scalatest" % "3.2.15" % "test"
)

// Configurações do Assembly para criar JAR fat
assembly / assemblyMergeStrategy := {
  case PathList("META-INF", xs @ _*) => 
    xs match {
      case "MANIFEST.MF" :: Nil => MergeStrategy.discard
      case "services" :: _ => MergeStrategy.concat
      case _ => MergeStrategy.discard
    }
  case "reference.conf" => MergeStrategy.concat
  case _ => MergeStrategy.first
}

// Exclude Spark and Hadoop from assembly (provided by Glue)
assembly / assemblyExcludedJars := {
  val cp = (assembly / fullClasspath).value
  cp.filter { jar =>
    jar.data.getName.startsWith("spark-") ||
    jar.data.getName.startsWith("hadoop-") ||
    jar.data.getName.startsWith("scala-library")
  }
}

// Nome do JAR do Assembly
assembly / assemblyJarName := s"${name.value}_${scalaBinaryVersion.value}-${version.value}.jar"

// Opções do compilador
scalacOptions ++= Seq(
  "-encoding", "UTF-8",
  "-deprecation",
  "-feature",
  "-unchecked",
  "-Xlint"
)
